import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const source = stripTypeScriptTypes(
  readFileSync(new URL('./io-client.ts', import.meta.url), 'utf8').replace(/^import .*;\n/gm, ''),
);

function fixture(hasOpener = true) {
  const handlers = new Map();
  const opener = hasOpener ? {} : null;
  const parent = { opener, postMessage() {} };
  const play = { disabled: true, addEventListener() {} };
  const window = { addEventListener: (type, callback) => handlers.set(type, callback) };
  runInNewContext(source, {
    window, parent, AbortController,
    location: { origin: 'https://io.example.test' },
    document: { querySelector: (selector) => selector === '#play' ? play : {} },
  });
  const send = (event) => handlers.get('message')({
    origin: 'https://io.example.test',
    source: opener,
    data: { ticket: 'fixture', hostId: 1, appId: 1, transport: 'websocket' },
    ...event,
  });
  return { play, send, opener, parent };
}

test('IO iframe accepts configuration sent by its popup owner and parent', () => {
  for (const kind of ['opener', 'parent']) {
    const value = fixture();
    value.send({ source: value[kind] });
    assert.equal(value.play.disabled, false);
    value.play.disabled = true;
    value.send({ source: value[kind] });
    assert.equal(value.play.disabled, true, 'configuration remains single-use');
  }
});

test('IO iframe rejects foreign origins, unrelated windows and null senders', () => {
  for (const hasOpener of [true, false]) {
    const value = fixture(hasOpener);
    value.send({ origin: 'https://attacker.example', source: value.parent });
    assert.equal(value.play.disabled, true);
    value.send({ source: {} });
    assert.equal(value.play.disabled, true);
    value.send({ source: null });
    assert.equal(value.play.disabled, true);
    value.send({ source: value.parent });
    assert.equal(value.play.disabled, false);
  }
});
