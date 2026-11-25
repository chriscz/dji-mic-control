// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../log/app_logger.dart';
import '../../state/mic_controller.dart';
import '../theme.dart';

/// Collapsible on-screen Diagnostics fold + hideable Pending Operations strip.
class DiagnosticsFold extends StatefulWidget {
  const DiagnosticsFold({
    super.key,
    required this.controller,
  });

  final MicController controller;

  @override
  State<DiagnosticsFold> createState() => _DiagnosticsFoldState();
}

class _DiagnosticsFoldState extends State<DiagnosticsFold> {
  final ScrollController _scrollController = ScrollController();
  LogLevel? _filter;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final controller = widget.controller;
    final logger = controller.services.logger;
    final expanded = controller.config.showDiagnosticsFold;
    final pendingOps = controller.pendingOperations;
    final showPending = controller.config.showPendingStrip && pendingOps.isNotEmpty;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[controller, logger]),
      builder: (context, _) {
        final entries = logger.entries
            .where((e) => _filter == null || e.level == _filter)
            .toList()
            .reversed
            .toList();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (showPending)
              Container(
                key: const Key('pending-ops-strip'),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  border: Border(top: BorderSide(color: colors.accent.withValues(alpha: 0.3))),
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: pendingOps.map((op) {
                          return Text(
                            '${op.stage}: ${op.label} -> ${op.value}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.text),
                          );
                        }).toList(),
                      ),
                    ),
                    Tooltip(
                      message: 'Hide pending operations bar (re-enable in Preferences)',
                      child: IconButton(
                        key: const Key('hide-pending-strip-btn'),
                        icon: Icon(Icons.visibility_off_outlined, size: 15, color: colors.textDim),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                        onPressed: () => controller.setShowPendingStrip(false),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              decoration: BoxDecoration(
                color: colors.bgPanel,
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  InkWell(
                    key: const Key('diagnostics-fold-header'),
                    onTap: controller.toggleDiagnosticsFold,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            expanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                            size: 18,
                            color: colors.textDim,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Diagnostics',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.text),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${logger.entries.length} entries  |  ${controller.snapshot.backendName}',
                            style: TextStyle(fontSize: 11.5, color: colors.textDim),
                          ),
                          if (pendingOps.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                color: colors.accentSoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${pendingOps.length} pending',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.accent),
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (expanded) ...<Widget>[
                            for (final level in <LogLevel?>[null, ...LogLevel.values])
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () => setState(() => _filter = level),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _filter == level ? colors.accentSoft : Colors.transparent,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: _filter == level
                                            ? colors.accent.withValues(alpha: 0.4)
                                            : colors.border,
                                      ),
                                    ),
                                    child: Text(
                                      level == null ? 'ALL' : level.tag,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: _filter == level ? colors.accent : colors.textDim,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            TextButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: logger.dumpText()));
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Copy', style: TextStyle(fontSize: 11.5)),
                            ),
                            TextButton(
                              onPressed: logger.clear,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Clear', style: TextStyle(fontSize: 11.5)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (expanded)
                    Container(
                      key: const Key('diagnostics-fold-body'),
                      height: 170,
                      padding: const EdgeInsets.fromLTRB(12, 6, 4, 8),
                      decoration: BoxDecoration(
                        color: colors.bg,
                        border: Border(top: BorderSide(color: colors.border)),
                      ),
                      child: entries.isEmpty
                          ? Center(
                              child: Text(
                                'No log entries yet. Toggle a setting to see TX/confirm logs.',
                                style: TextStyle(fontSize: 12, color: colors.textFaint),
                              ),
                            )
                          : Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.only(right: 14),
                                itemCount: entries.length,
                                itemBuilder: (context, idx) {
                                  final entry = entries[idx];
                                  return SelectableText(
                                    entry.format(),
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                      color: entry.level == LogLevel.error
                                          ? colors.danger
                                          : entry.level == LogLevel.warn
                                              ? colors.warn
                                              : colors.text,
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
