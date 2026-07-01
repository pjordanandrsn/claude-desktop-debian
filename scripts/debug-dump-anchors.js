#!/usr/bin/env node
// TEMPORARY diagnostic — dumps minified-source context around the
// patch anchors that went MISS on 1.17377.1 (vmclient-log-gate,
// vm-assignment-linux-gate, econnrefused-on-linux). Runs in CI via
// debug-anchors.yml because this sandbox can't fetch the installer.
// Both files are removed once the new anchors are derived.
'use strict';

const fs = require('fs');

const indexJs = process.argv[2];
if (!indexJs) {
    console.error('usage: debug-dump-anchors.js <index.js>');
    process.exit(1);
}
const code = fs.readFileSync(indexJs, 'utf8');
console.log(`index.js length: ${code.length}`);

function dumpAll(label, needle, before, after, cap) {
    console.log(`\n########## ${label} ##########`);
    let idx = -1;
    let n = 0;
    while ((idx = code.indexOf(needle, idx + 1)) !== -1 && n < cap) {
        n++;
        const start = Math.max(0, idx - before);
        const end = Math.min(code.length, idx + needle.length + after);
        console.log(`--- occurrence ${n} @ ${idx} ---`);
        console.log(code.substring(start, end));
    }
    if (n === 0) console.log('(no occurrences)');
    console.log(`### total shown: ${n} ###`);
}

// The two vmClient gates (Patch 2a/2b) anchor on this string; the
// IDENT? prefix match returned null on 1.17377.1.
dumpAll('vmClient (TypeScript)', 'vmClient (TypeScript)', 500, 500, 5);

// Patch 6 anchors on this error string; the ENOENT check was not
// within 300 chars before it, and the retry delay not within 300
// after. Dump a much wider window to see the restructured loop.
dumpAll(
    'VM service not running',
    'VM service not running. The service failed to start.',
    2000,
    2000,
    3
);

// Where do ENOENT checks live now?
dumpAll('ENOENT sites', 'ENOENT', 250, 120, 20);

// Does upstream now handle ECONNREFUSED itself?
dumpAll('ECONNREFUSED sites', 'ECONNREFUSED', 250, 120, 10);
