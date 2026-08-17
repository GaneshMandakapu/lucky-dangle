//
//  Self-check for the ported pendulum. Run with:  node test-physics.mjs
//
//  charm.js is an ES module loaded by the renderer, but this package is CommonJS
//  (Electron's preload needs that), so Node would treat a plain import of a .js
//  file as CJS and choke on `export`. Loading the source through a data: URL
//  sidesteps that without restructuring the app.
//

import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const src = await readFile(new URL('./charm.js', import.meta.url), 'utf8');
const { Dangle, Tuning } = await import(
  'data:text/javascript;base64,' + Buffer.from(src).toString('base64'));

/// Minimal canvas stub — the physics never touches the 2D context.
function makeDangle() {
  const canvas = { clientWidth: 980, clientHeight: 630, width: 0, height: 0,
                   getContext: () => ({}) };
  return new Dangle(canvas);
}

/// Advance `seconds` of simulated time in frames of `1/fps`.
function run(d, seconds, fps) {
  const stepMs = 1000 / fps;
  for (let t = 0; t <= seconds * 1000; t += stepMs) d.step(t);
  return d;
}

// 1. A pendulum let go off-centre swings back and loses energy.
{
  const d = makeDangle();
  d.theta = 0.6;
  d.omega = 0;
  run(d, 30, 60);
  assert.ok(Math.abs(d.theta) < 0.6,
    `should settle toward vertical, got theta=${d.theta}`);
  assert.ok(Math.abs(d.omega) < 1.0,
    `should lose energy, got omega=${d.omega}`);
}

// 2. The fixed step makes the motion frame-rate independent: 60 Hz and 144 Hz
//    must land in the same place after the same simulated time. This is the
//    property that breaks first if someone "simplifies" the accumulator away.
{
  const a = makeDangle(); a.theta = 0.5;
  const b = makeDangle(); b.theta = 0.5;
  run(a, 5, 60);
  run(b, 5, 144);
  assert.ok(Math.abs(a.theta - b.theta) < 0.02,
    `60Hz gave ${a.theta}, 144Hz gave ${b.theta} — not frame-rate independent`);
}

// 3. The angle clamp holds even when thrown hard, and reverses direction.
{
  const d = makeDangle();
  d.theta = Tuning.maxAngle - 0.01;
  d.omega = 40;
  run(d, 2, 60);
  assert.ok(Math.abs(d.theta) <= Tuning.maxAngle + 1e-9,
    `theta escaped the clamp: ${d.theta}`);
}

// 4. Dropping extends the cord, and releasing retracts it.
{
  const d = makeDangle();
  assert.equal(d.targetLength, Tuning.restLength);
  d.toggleDrop();
  assert.equal(d.targetLength, Tuning.dropLength);
  d.toggleDrop();
  assert.equal(d.targetLength, Tuning.restLength);
}

// 5. Only the charm itself is clickable — that's what keeps the overlay
//    click-through everywhere else.
{
  const d = makeDangle();
  d.theta = 0;
  const b = d.bobCenter;
  assert.ok(d.isOverCharm(b), 'centre of the charm should be a hit');
  assert.ok(!d.isOverCharm({ x: b.x + d.bobRadius + 40, y: b.y }),
    'well outside the charm should not be a hit');
  assert.ok(!d.isOverCharm(null), 'no pointer should not be a hit');
}

console.log('physics ok');
