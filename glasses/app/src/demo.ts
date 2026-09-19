/** Public, offline fixtures for photographing the real lens renderer. */
import type { Snapshot } from './protocol';

export const demoSnapshot: Snapshot = {
  protocol_version: 1, type: 'snapshot', revision: 1, at: 0,
  inventory_valid: true, stale: false, controls_allowed: false,
  summary: '5 Spaces', wake: [],
  agents: [
    { id: 'demo-landing', name: 'landing-page', kind: 'codex', space: 'landing-page', status: 'done', pinned: false, hostName: 'devbox' },
    { id: 'demo-auth', name: 'fix-auth', kind: 'claude', space: 'fix-auth', status: 'working', pinned: false, hostName: 'devbox' },
    { id: 'demo-payments', name: 'payments', kind: 'codex', space: 'payments', status: 'blocked', pinned: false, hostName: 'devbox' },
    { id: 'demo-mobile', name: 'mobile-polish', kind: 'claude', space: 'mobile-polish', status: 'working', pinned: false, hostName: 'laptop' },
    { id: 'demo-docs', name: 'docs', kind: 'codex', space: 'docs', status: 'idle', pinned: false, hostName: 'laptop' },
  ],
};

export const demoOutput = [
  '> Make the landing page work on mobile.',
  'Updated the responsive layout.',
  'The terminal controls stay visible.',
  'Checked small phones and desktop widths.',
  'Build passed. Ready for your review.',
];
