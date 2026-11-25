// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

use std::ffi::{c_char, CString};
use std::io::ErrorKind;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use futures_lite::future;
use nusb::transfer::RequestBuffer;
use nusb::Interface;

const ERR_OK: i32 = 0;
const ERR_GENERIC: i32 = -1;
const ERR_PERMISSION: i32 = -13;
const ERR_DISCONNECTED: i32 = -19;

/// Opaque handle passed across the C ABI to Dart's `NusbFfiTransport`.
pub struct DjiUsbHandle {
    iface: Interface,
    ep_in: u8,
    ep_out: u8,
    closed: Arc<AtomicBool>,
}

fn escape_json(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

fn format_devices_json(entries: &[(u8, u8, u16, u16, Option<&str>)]) -> String {
    let mut out = String::from("[");
    for (idx, (bus, addr, vid, pid, serial)) in entries.iter().enumerate() {
        if idx > 0 {
            out.push(',');
        }
        let id = format!("usb-{bus}-{addr}");
        let serial_json = match serial {
            Some(s) if !s.is_empty() => format!("\"{}\"", escape_json(s)),
            _ => "null".to_string(),
        };
        out.push_str(&format!(
            "{{\"id\":\"{id}\",\"bus\":{bus},\"address\":{addr},\"vid\":{vid},\"pid\":{pid},\"serial\":{serial_json}}}"
        ));
    }
    out.push(']');
    out
}

/// Enumerate all USB devices on the host via `nusb` and return a newly
/// allocated UTF-8 JSON C string. Caller must free with `dji_usb_str_free`.
#[no_mangle]
pub extern "C" fn dji_usb_list_json() -> *mut c_char {
    let json = match nusb::list_devices() {
        Ok(iter) => {
            let owned: Vec<(u8, u8, u16, u16, Option<String>)> = iter
                .map(|d| {
                    (
                        d.bus_number(),
                        d.device_address(),
                        d.vendor_id(),
                        d.product_id(),
                        d.serial_number().map(|s| s.to_string()),
                    )
                })
                .collect();
            let refs: Vec<(u8, u8, u16, u16, Option<&str>)> = owned
                .iter()
                .map(|(b, a, v, p, s)| (*b, *a, *v, *p, s.as_deref()))
                .collect();
            format_devices_json(&refs)
        }
        Err(_) => "[]".to_string(),
    };
    CString::new(json)
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

/// Free a string returned by `dji_usb_list_json`.
///
/// # Safety
/// `ptr` must be null or a pointer previously returned by `dji_usb_list_json`.
#[no_mangle]
pub unsafe extern "C" fn dji_usb_str_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

/// Open a USB device by bus/address and detach + claim only `interface_num`.
///
/// On failure returns null and writes an error code into `out_err` (if non-null):
/// `-13` for permission denied, `-19` if device not found, `-1` for other errors.
///
/// # Safety
/// `out_err` may be null or a valid writable pointer to `i32`.
#[no_mangle]
pub unsafe extern "C" fn dji_usb_open(
    bus: u8,
    address: u8,
    interface_num: u8,
    ep_in: u8,
    ep_out: u8,
    out_err: *mut i32,
) -> *mut DjiUsbHandle {
    let set_err = |code: i32| {
        if !out_err.is_null() {
            *out_err = code;
        }
    };

    let Ok(devices) = nusb::list_devices() else {
        set_err(ERR_GENERIC);
        return std::ptr::null_mut();
    };

    let Some(info) = devices
        .into_iter()
        .find(|d| d.bus_number() == bus && d.device_address() == address)
    else {
        set_err(ERR_DISCONNECTED);
        return std::ptr::null_mut();
    };

    let dev = match info.open() {
        Ok(d) => d,
        Err(e) => {
            set_err(if e.kind() == ErrorKind::PermissionDenied {
                ERR_PERMISSION
            } else {
                ERR_GENERIC
            });
            return std::ptr::null_mut();
        }
    };

    let iface = match dev.detach_and_claim_interface(interface_num) {
        Ok(i) => i,
        Err(e) => {
            set_err(if e.kind() == ErrorKind::PermissionDenied {
                ERR_PERMISSION
            } else {
                ERR_GENERIC
            });
            return std::ptr::null_mut();
        }
    };

    set_err(ERR_OK);
    Box::into_raw(Box::new(DjiUsbHandle {
        iface,
        ep_in,
        ep_out,
        closed: Arc::new(AtomicBool::new(false)),
    }))
}

/// Read up to `buf_len` bytes from the claimed bulk IN endpoint.
///
/// Returns number of bytes read (`>= 0`), or `-19` on disconnect/close.
///
/// # Safety
/// `handle` must be a valid handle from `dji_usb_open`, and `buf` must point
/// to at least `buf_len` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn dji_usb_bulk_in(
    handle: *mut DjiUsbHandle,
    buf: *mut u8,
    buf_len: usize,
) -> i32 {
    if handle.is_null() || buf.is_null() || buf_len == 0 {
        return ERR_GENERIC;
    }
    let h = &*handle;
    if h.closed.load(Ordering::Relaxed) {
        return ERR_DISCONNECTED;
    }

    let comp = future::block_on(h.iface.bulk_in(h.ep_in, RequestBuffer::new(buf_len)));
    if comp.status.is_err() {
        return ERR_DISCONNECTED;
    }
    let n = comp.data.len().min(buf_len);
    std::ptr::copy_nonoverlapping(comp.data.as_ptr(), buf, n);
    n as i32
}

/// Write `len` bytes to the claimed bulk OUT endpoint.
///
/// Returns `0` on success, `-19` if disconnected, `-1` on other error.
///
/// # Safety
/// `handle` must be valid and `data` must point to at least `len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn dji_usb_bulk_out(
    handle: *mut DjiUsbHandle,
    data: *const u8,
    len: usize,
) -> i32 {
    if handle.is_null() || data.is_null() || len == 0 {
        return ERR_GENERIC;
    }
    let h = &*handle;
    if h.closed.load(Ordering::Relaxed) {
        return ERR_DISCONNECTED;
    }
    let slice = std::slice::from_raw_parts(data, len).to_vec();
    let comp = future::block_on(h.iface.bulk_out(h.ep_out, slice));
    if comp.status.is_ok() {
        ERR_OK
    } else {
        ERR_DISCONNECTED
    }
}

/// Release the claimed USB interface and free the handle.
///
/// # Safety
/// `handle` must be null or a pointer returned by `dji_usb_open` not yet closed.
#[no_mangle]
pub unsafe extern "C" fn dji_usb_close(handle: *mut DjiUsbHandle) {
    if !handle.is_null() {
        let h = Box::from_raw(handle);
        h.closed.store(true, Ordering::Relaxed);
        drop(h);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_json_and_escapes_serials() {
        let entries = [
            (1u8, 7u8, 0x2ca3u16, 0x4011u16, Some("ABC\"123")),
            (2u8, 3u8, 0x1d6bu16, 0x0002u16, None),
        ];
        let json = format_devices_json(&entries);
        assert!(json.contains("\"id\":\"usb-1-7\""));
        assert!(json.contains("\"vid\":11427"));
        assert!(json.contains("\"pid\":16401"));
        assert!(json.contains("\"serial\":\"ABC\\\"123\""));
        assert!(json.contains("\"serial\":null"));
    }

    #[test]
    fn list_json_returns_valid_c_string() {
        let ptr = dji_usb_list_json();
        assert!(!ptr.is_null());
        unsafe {
            let s = std::ffi::CStr::from_ptr(ptr).to_str().expect("utf8");
            assert!(s.starts_with('['));
            assert!(s.ends_with(']'));
            dji_usb_str_free(ptr);
        }
    }
}
