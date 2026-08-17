//
//  Lucky Dangle — charm rendering and physics.
//
//  Ported from main.swift. The canvas is flipped to a y-up coordinate system in
//  render() so every drawing routine below reads the same as the CoreGraphics
//  original: origin at the charm's centre, +y pointing up.
//

const TAU = Math.PI * 2;

// ─────────────────────────────────────────────────────────────
// Tuning — kept identical to main.swift so the feel matches
// ─────────────────────────────────────────────────────────────

export const Tuning = {
  restLength: 190,
  dropLength: 400,
  dropSeconds: 4.0,
  gravity: 2000,
  damping: 0.9955,     // per 1/60 s step
  maxAngle: 1.15,
  mouseDrive: 0.00022,
  mouseDriveNear: 0.0011,
  breeze: 1.0,
  stepHz: 60,          // fixed physics step; render runs at the display's rate

  glintPeriod: 4.2,
  glintTravel: 1.15,
  glowStrength: 1.0,
  sparkles: true,
};

const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

/// srgb(0…1) → canvas colour string, matching the Swift `srgb` helper.
const srgb = (r, g, b, a = 1) =>
  `rgba(${Math.round(r * 255)},${Math.round(g * 255)},${Math.round(b * 255)},${a})`;

// ─────────────────────────────────────────────────────────────
// Drawing helpers
// ─────────────────────────────────────────────────────────────

function ell(ctx, x, y, w, h) {
  ctx.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, TAU);
}

/// Clip to `path` and flood it with a radial gradient lit from (cx, cy).
/// The flood rect reproduces CoreGraphics' `drawsAfterEndLocation`.
function fillRadial(ctx, path, cx, cy, radius, stops) {
  ctx.save();
  ctx.beginPath();
  path(ctx);
  ctx.clip();
  const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.max(radius, 0.01));
  for (const [c, p] of stops) g.addColorStop(clamp(p, 0, 1), c);
  ctx.fillStyle = g;
  ctx.fillRect(-4000, -4000, 8000, 8000);
  ctx.restore();
}

/// Same, with a linear gradient running along `angle`.
function fillLinear(ctx, path, angle, extent, stops) {
  ctx.save();
  ctx.beginPath();
  path(ctx);
  ctx.clip();
  const dx = Math.cos(angle) * extent, dy = Math.sin(angle) * extent;
  const g = ctx.createLinearGradient(-dx, -dy, dx, dy);
  for (const [c, p] of stops) g.addColorStop(clamp(p, 0, 1), c);
  ctx.fillStyle = g;
  ctx.fillRect(-4000, -4000, 8000, 8000);
  ctx.restore();
}

/// Soft blurred-looking specular blob (fake blur via a radial fade).
function specular(ctx, x, y, size, squash = 0.62, angle = -0.5, alpha = 0.6) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(angle);
  ctx.scale(1, squash);
  const g = ctx.createRadialGradient(0, 0, 0, 0, 0, Math.max(size, 0.01));
  g.addColorStop(0, srgb(1, 1, 1, alpha));
  g.addColorStop(0.45, srgb(1, 1, 1, alpha * 0.45));
  g.addColorStop(1, srgb(1, 1, 1, 0));
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(0, 0, size, 0, TAU);
  ctx.fill();
  ctx.restore();
}

/// Four-point sparkle centred on the origin.
function starPath(ctx, s) {
  const k = s * 0.16;
  ctx.moveTo(0, s);
  ctx.quadraticCurveTo(k, k, s, 0);
  ctx.quadraticCurveTo(k, -k, 0, -s);
  ctx.quadraticCurveTo(-k, -k, -s, 0);
  ctx.quadraticCurveTo(-k, k, 0, s);
  ctx.closePath();
}

// ─────────────────────────────────────────────────────────────
// Charms
// ─────────────────────────────────────────────────────────────

export const CHARMS = {
  nazar: {
    title: 'Nazar — evil eye (Türkiye)',
    baseRadius: 58,
    tint: srgb(0.25, 0.50, 1.00),
    silhouette: (ctx, r) => ell(ctx, -r, -r, r * 2, r * 2),
    body(ctx, r) {
      const litX = -r * 0.34, litY = r * 0.34;
      const glass = (c) => ell(c, -r, -r, r * 2, r * 2);

      fillRadial(ctx, glass, litX, litY, r * 1.9, [
        [srgb(0.34, 0.56, 1.00), 0.00],
        [srgb(0.11, 0.30, 0.88), 0.42],
        [srgb(0.04, 0.13, 0.58), 0.80],
        [srgb(0.02, 0.07, 0.36), 1.00],
      ]);
      fillRadial(ctx, (c) => ell(c, -r * 0.66, -r * 0.66, r * 1.32, r * 1.32),
        -r * 0.2, r * 0.2, r * 1.1,
        [[srgb(1, 1, 1), 0], [srgb(0.94, 0.96, 0.99), 0.6], [srgb(0.82, 0.86, 0.92), 1]]);
      fillRadial(ctx, (c) => ell(c, -r * 0.44, -r * 0.44, r * 0.88, r * 0.88),
        -r * 0.14, r * 0.16, r * 0.8,
        [[srgb(0.62, 0.88, 1.00), 0], [srgb(0.36, 0.72, 0.94), 0.5],
         [srgb(0.13, 0.44, 0.78), 1]]);
      fillRadial(ctx, (c) => ell(c, -r * 0.20, -r * 0.20, r * 0.40, r * 0.40),
        -r * 0.06, r * 0.07, r * 0.4,
        [[srgb(0.16, 0.17, 0.22), 0], [srgb(0.02, 0.02, 0.05), 1]]);

      ctx.save();
      ctx.beginPath(); glass(ctx); ctx.clip();
      ctx.strokeStyle = srgb(0, 0, 0, 0.28);
      ctx.lineWidth = r * 0.10;
      ctx.beginPath(); glass(ctx); ctx.stroke();
      ctx.restore();

      specular(ctx, -r * 0.44, r * 0.46, r * 0.40, 0.55, -0.55, 0.75);
      specular(ctx, r * 0.38, -r * 0.46, r * 0.22, 0.6, -0.5, 0.35);
    },
  },

  clover: {
    title: 'Four-leaf clover (Ireland)',
    baseRadius: 52,
    tint: srgb(0.35, 0.85, 0.35),
    silhouette(ctx, r) {
      for (let i = 0; i < 4; i++) {
        ctx.save();
        ctx.rotate((i * Math.PI) / 2);
        ell(ctx, -r * 0.33, r * 0.10, r * 0.66, r * 0.86);
        ctx.restore();
      }
      ell(ctx, -r * 0.16, -r * 0.16, r * 0.32, r * 0.32);
    },
    body(ctx, r) {
      ctx.strokeStyle = srgb(0.14, 0.40, 0.15);
      ctx.lineWidth = Math.max(2, r * 0.09);
      ctx.lineCap = 'round';
      ctx.beginPath();
      ctx.moveTo(0, -r * 0.15);
      ctx.bezierCurveTo(-r * 0.05, -r * 0.55, r * 0.25, -r * 0.7, r * 0.22, -r * 1.05);
      ctx.stroke();

      for (let i = 0; i < 4; i++) {
        ctx.save();
        ctx.rotate((i * Math.PI) / 2);
        fillRadial(ctx, (c) => ell(c, -r * 0.33, r * 0.10, r * 0.66, r * 0.86),
          -r * 0.10, r * 0.42, r * 0.75,
          [[srgb(0.52, 0.86, 0.40), 0], [srgb(0.26, 0.66, 0.26), 0.55],
           [srgb(0.11, 0.42, 0.14), 1]]);
        ctx.strokeStyle = srgb(0.09, 0.34, 0.11, 0.5);
        ctx.lineWidth = Math.max(1, r * 0.035);
        ctx.beginPath();
        ctx.moveTo(0, r * 0.16);
        ctx.lineTo(0, r * 0.88);
        ctx.stroke();
        specular(ctx, -r * 0.12, r * 0.62, r * 0.20, 0.7, 0.3, 0.45);
        ctx.restore();
      }

      fillRadial(ctx, (c) => ell(c, -r * 0.15, -r * 0.15, r * 0.30, r * 0.30),
        -r * 0.04, r * 0.05, r * 0.3,
        [[srgb(0.34, 0.70, 0.30), 0], [srgb(0.10, 0.36, 0.12), 1]]);
    },
  },

  horseshoe: {
    title: 'Horseshoe (Europe)',
    baseRadius: 54,
    tint: srgb(1.00, 0.82, 0.30),
    // The Swift version strokes an arc into a path; canvas has no path-stroking
    // primitive, so the silhouette is the stroked arc drawn with a fat round pen.
    silhouette(ctx, r) {
      ctx.arc(0, 0, r * 0.62, -0.42, Math.PI + 0.42, false);
    },
    silhouetteIsStroke: true,
    silhouetteWidth: (r) => r * 0.34,
    body(ctx, r) {
      const sil = (c) => {
        c.arc(0, 0, r * 0.62, -0.42, Math.PI + 0.42, false);
      };
      // clip through the stroked arc, then flood with the metal gradient
      ctx.save();
      ctx.beginPath(); sil(ctx);
      ctx.lineWidth = r * 0.34; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      ctx.strokeStyle = srgb(0.8, 0.65, 0.2);
      const g = ctx.createLinearGradient(-Math.cos(1.15) * r, -Math.sin(1.15) * r,
                                          Math.cos(1.15) * r, Math.sin(1.15) * r);
      g.addColorStop(0.00, srgb(1.00, 0.93, 0.66));
      g.addColorStop(0.35, srgb(0.93, 0.76, 0.28));
      g.addColorStop(0.70, srgb(0.72, 0.53, 0.12));
      g.addColorStop(1.00, srgb(0.52, 0.36, 0.07));
      ctx.strokeStyle = g;
      ctx.stroke();
      ctx.restore();

      // polished inner bands, clipped to the shoe
      ctx.save();
      ctx.beginPath(); sil(ctx);
      ctx.lineWidth = r * 0.34; ctx.lineCap = 'round';
      ctx.strokeStyle = 'rgba(0,0,0,1)';
      // emulate clip-to-stroke by drawing the bands with matching round caps
      ctx.lineWidth = r * 0.10;
      ctx.strokeStyle = srgb(1, 0.98, 0.86, 0.55);
      ctx.beginPath();
      ctx.arc(0, 0, r * 0.70, 0.30, Math.PI - 0.30, false);
      ctx.stroke();
      ctx.strokeStyle = srgb(0.35, 0.24, 0.04, 0.45);
      ctx.beginPath();
      ctx.arc(0, 0, r * 0.50, 0.20, Math.PI - 0.20, false);
      ctx.stroke();
      ctx.restore();

      for (let i = 0; i < 7; i++) {
        const a = -0.2 + (i / 6) * (Math.PI + 0.4);
        const px = Math.cos(a) * r * 0.62, py = Math.sin(a) * r * 0.62;
        fillRadial(ctx, (c) => ell(c, px - r * 0.058, py - r * 0.058, r * 0.116, r * 0.116),
          px, py + r * 0.03, r * 0.12,
          [[srgb(0.30, 0.21, 0.05), 0], [srgb(0.10, 0.07, 0.01), 1]]);
      }
    },
  },

  knot: {
    title: 'Lucky knot (China)',
    baseRadius: 52,
    tint: srgb(1.00, 0.32, 0.26),
    silhouette(ctx, r) {
      ctx.save();
      ctx.rotate(Math.PI / 4);
      ctx.roundRect(-r * 0.60, -r * 0.60, r * 1.2, r * 1.2, r * 0.30);
      ctx.restore();
    },
    body(ctx, r) {
      ctx.strokeStyle = srgb(0.62, 0.11, 0.10);
      ctx.lineWidth = Math.max(1.5, r * 0.07);
      ctx.lineCap = 'round';
      for (const dx of [-r * 0.16, 0, r * 0.16]) {
        ctx.beginPath();
        ctx.moveTo(dx * 0.4, -r * 0.5);
        ctx.lineTo(dx, -r * 1.15);
        ctx.stroke();
      }

      const outer = (c) => c.roundRect(-r * 0.60, -r * 0.60, r * 1.2, r * 1.2, r * 0.30);
      const inner = (c) => c.roundRect(-r * 0.20, -r * 0.20, r * 0.4, r * 0.4, r * 0.12);

      ctx.save();
      ctx.rotate(Math.PI / 4);
      ctx.beginPath(); outer(ctx); inner(ctx);
      ctx.clip('evenodd');
      const g = ctx.createRadialGradient(-r * 0.25, r * 0.25, 0, -r * 0.25, r * 0.25, r * 1.4);
      g.addColorStop(0.00, srgb(1.00, 0.44, 0.36));
      g.addColorStop(0.50, srgb(0.85, 0.19, 0.16));
      g.addColorStop(1.00, srgb(0.52, 0.06, 0.06));
      ctx.fillStyle = g;
      ctx.fillRect(-4000, -4000, 8000, 8000);
      ctx.restore();

      ctx.save();
      ctx.rotate(Math.PI / 4);
      ctx.strokeStyle = srgb(1.00, 0.85, 0.45, 0.95);
      ctx.lineWidth = Math.max(1, r * 0.055);
      ctx.beginPath(); outer(ctx); ctx.stroke();
      ctx.strokeStyle = srgb(1.00, 0.85, 0.45, 0.6);
      ctx.beginPath(); inner(ctx); ctx.stroke();
      ctx.restore();

      specular(ctx, -r * 0.26, r * 0.30, r * 0.30, 0.55, -0.7, 0.5);
    },
  },

  dog: {
    title: 'Lucky dog — faithful guardian',
    baseRadius: 54,
    tint: srgb(1.00, 0.74, 0.40),
    silhouette(ctx, r) {
      for (const side of [-1, 1]) {
        ctx.save();
        ctx.translate(side * r * 0.70, r * 0.04);
        ctx.rotate(side * -0.28);
        ell(ctx, -r * 0.25, -r * 0.48, r * 0.50, r * 0.96);
        ctx.restore();
      }
      ell(ctx, -r * 0.80, -r * 0.73, r * 1.60, r * 1.50);
    },
    body(ctx, r) {
      const litX = -r * 0.34, litY = r * 0.42;

      // collar and tag, below the chin — drawn first so the head overlaps them
      fillLinear(ctx, (c) => c.roundRect(-r * 0.40, -r * 0.80, r * 0.80, r * 0.24, r * 0.12),
        Math.PI / 2, r * 0.2,
        [[srgb(0.86, 0.20, 0.18), 0], [srgb(0.52, 0.07, 0.07), 1]]);
      fillRadial(ctx, (c) => ell(c, -r * 0.15, -r * 0.98, r * 0.30, r * 0.30),
        -r * 0.05, -r * 0.78, r * 0.30,
        [[srgb(1.00, 0.93, 0.60), 0], [srgb(0.90, 0.71, 0.24), 0.6],
         [srgb(0.62, 0.44, 0.09), 1]]);

      // droopy ears, behind the head
      for (const side of [-1, 1]) {
        ctx.save();
        ctx.translate(side * r * 0.70, r * 0.04);
        ctx.rotate(side * -0.28);
        fillRadial(ctx, (c) => ell(c, -r * 0.25, -r * 0.48, r * 0.50, r * 0.96),
          litX, litY, r * 1.9,
          [[srgb(0.52, 0.33, 0.17), 0.00], [srgb(0.38, 0.23, 0.11), 0.55],
           [srgb(0.24, 0.13, 0.06), 1.00]]);
        ctx.restore();
      }

      fillRadial(ctx, (c) => ell(c, -r * 0.80, -r * 0.73, r * 1.60, r * 1.50),
        litX, litY, r * 1.7,
        [[srgb(0.89, 0.70, 0.44), 0.00], [srgb(0.76, 0.55, 0.31), 0.45],
         [srgb(0.56, 0.37, 0.19), 0.82], [srgb(0.40, 0.25, 0.12), 1.00]]);

      // pale blaze down the forehead
      fillRadial(ctx, (c) => ell(c, -r * 0.15, -r * 0.30, r * 0.30, r * 1.00),
        0, r * 0.30, r * 0.6,
        [[srgb(0.97, 0.90, 0.76, 0.55), 0], [srgb(0.97, 0.90, 0.76, 0), 1]]);

      fillRadial(ctx, (c) => ell(c, -r * 0.45, -r * 0.68, r * 0.90, r * 0.66),
        -r * 0.12, -r * 0.20, r * 0.8,
        [[srgb(0.99, 0.94, 0.85), 0], [srgb(0.93, 0.85, 0.72), 0.6],
         [srgb(0.80, 0.69, 0.55), 1]]);

      fillRadial(ctx, (c) => c.roundRect(-r * 0.17, -r * 0.20, r * 0.34, r * 0.25, r * 0.11),
        -r * 0.05, -r * 0.02, r * 0.3,
        [[srgb(0.28, 0.26, 0.30), 0], [srgb(0.06, 0.05, 0.07), 1]]);

      ctx.strokeStyle = srgb(0.34, 0.24, 0.16, 0.85);
      ctx.lineWidth = Math.max(1, r * 0.045);
      ctx.lineCap = 'round';
      for (const side of [-1, 1]) {
        ctx.beginPath();
        ctx.moveTo(0, -r * 0.22);
        ctx.quadraticCurveTo(side * r * 0.03, -r * 0.42, side * r * 0.20, -r * 0.44);
        ctx.stroke();
      }

      for (const side of [-1, 1]) {
        const cx = side * r * 0.31, cy = r * 0.26;
        fillRadial(ctx, (c) => ell(c, cx - r * 0.14, cy - r * 0.15, r * 0.28, r * 0.30),
          cx - r * 0.04, cy + r * 0.05, r * 0.3,
          [[srgb(0.31, 0.22, 0.15), 0], [srgb(0.09, 0.05, 0.03), 1]]);
        specular(ctx, cx - r * 0.05, cy + r * 0.07, r * 0.075, 0.85, -0.5, 0.95);
      }

      specular(ctx, -r * 0.40, r * 0.50, r * 0.30, 0.55, -0.6, 0.45);
    },
  },
};

export const CHARM_ORDER = ['nazar', 'clover', 'horseshoe', 'knot', 'dog'];

// ─────────────────────────────────────────────────────────────
// Charm compositing — shadow, glow, body, glint, sparkles
// ─────────────────────────────────────────────────────────────

/// Trace a charm's silhouette into the current path. Horseshoe is a stroked
/// arc rather than a filled region, so it reports its pen width instead.
function traceSilhouette(ctx, def, r) {
  ctx.beginPath();
  def.silhouette(ctx, r);
}

function paintSilhouette(ctx, def, r, style) {
  traceSilhouette(ctx, def, r);
  if (def.silhouetteIsStroke) {
    ctx.lineWidth = def.silhouetteWidth(r);
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = style;
    ctx.stroke();
  } else {
    ctx.fillStyle = style;
    ctx.fill();
  }
}

function drawCharm(ctx, key, r, shine) {
  const def = CHARMS[key];

  // drop shadow. Canvas shadow offsets ignore the CTM, so this is screen-down.
  ctx.save();
  ctx.shadowColor = srgb(0, 0, 0, 0.30);
  ctx.shadowBlur = 12;
  ctx.shadowOffsetY = 4;
  paintSilhouette(ctx, def, r, srgb(0, 0, 0, 1));
  ctx.restore();

  // coloured halo
  if (shine.enabled && Tuning.glowStrength > 0) {
    const pulse = 0.5 + 0.5 * Math.sin(shine.time * 1.6);
    const a = (0.30 + 0.22 * pulse + 0.28 * shine.energy) * Tuning.glowStrength;
    ctx.save();
    ctx.shadowColor = def.tint.replace(/[\d.]+\)$/, `${Math.min(a, 0.85)})`);
    ctx.shadowBlur = 16 + 14 * shine.energy + 6 * pulse;
    paintSilhouette(ctx, def, r, def.tint);
    ctx.restore();
  }

  ctx.save();
  def.body(ctx, r);
  ctx.restore();

  if (!shine.enabled) return;
  drawGlint(ctx, def, r, shine);
  if (Tuning.sparkles) drawSparkles(ctx, r, shine);
}

function drawGlint(ctx, def, r, shine) {
  const period = Math.max(Tuning.glintPeriod - 2.2 * shine.energy, 1.0);
  const phase = shine.time % period;
  if (phase >= Tuning.glintTravel) return;

  const p = phase / Tuning.glintTravel;
  const ease = Math.sin(p * Math.PI);
  const intensity = (0.45 + 0.35 * shine.energy) * ease;
  const x = (p * 2 - 1) * r * 1.9;

  ctx.save();
  traceSilhouette(ctx, def, r);
  if (def.silhouetteIsStroke) {
    // no clip-to-stroke in canvas; approximate with the charm's bounding disc
    ctx.beginPath();
    ctx.arc(0, 0, r, 0, TAU);
  }
  ctx.clip();
  ctx.globalCompositeOperation = 'lighter';
  ctx.rotate(-0.62);
  const w = r * 0.85;
  const g = ctx.createLinearGradient(x - w, 0, x + w, 0);
  g.addColorStop(0, srgb(1, 1, 1, 0));
  g.addColorStop(0.42, srgb(1, 1, 1, intensity * 0.55));
  g.addColorStop(0.5, srgb(1, 1, 1, intensity));
  g.addColorStop(0.58, srgb(1, 1, 1, intensity * 0.55));
  g.addColorStop(1, srgb(1, 1, 1, 0));
  ctx.fillStyle = g;
  ctx.fillRect(-4000, -4000, 8000, 8000);
  ctx.restore();

  if (p > 0.35 && p < 0.75) {
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.translate(x * 0.5, r * 0.34);
    ctx.rotate(-0.62);
    ctx.fillStyle = srgb(1, 1, 1, intensity * 0.9);
    ctx.beginPath();
    starPath(ctx, r * 0.34);
    ctx.fill();
    ctx.restore();
  }
}

function drawSparkles(ctx, r, shine) {
  const spots = [
    [-0.62, 0.58, 0.26, 0.0],
    [0.70, 0.14, 0.20, 1.9],
    [0.18, -0.72, 0.17, 3.4],
  ];
  for (const [sx, sy, scale, offset] of spots) {
    const t = (shine.time + offset) % 3.1;
    if (t >= 0.8) continue;
    const a = Math.sin((t / 0.8) * Math.PI);
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.translate(sx * r, sy * r);
    ctx.rotate(t * 1.2);
    ctx.fillStyle = srgb(1, 1, 1, a * (0.55 + 0.35 * shine.energy));
    ctx.beginPath();
    starPath(ctx, r * scale * (0.6 + 0.4 * a));
    ctx.fill();
    ctx.restore();
  }
}

// ─────────────────────────────────────────────────────────────
// The dangle — physics and full-scene render
// ─────────────────────────────────────────────────────────────

export class Dangle {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');

    this.charm = 'nazar';
    this.sizeScale = 1.0;
    this.shimmer = true;

    this.theta = 0.10;
    this.omega = 0;
    this.length = Tuning.restLength;
    this.targetLength = Tuning.restLength;
    this.time = 0;
    this.dropUntil = null;

    this.cursor = null;      // pointer in window coords, from the main process
    this.prevCursor = null;
    this.dragging = false;
    this.dragMoved = 0;
    this.dragStarted = 0;

    this.accumulator = 0;
    this.lastFrame = 0;
    this.onHitChange = () => {};
    this.wasHit = null;
  }

  get width() { return this.canvas.clientWidth; }
  get height() { return this.canvas.clientHeight; }

  // anchor at the top centre; y measured up from the bottom, as in the Swift view
  get anchor() { return { x: this.width / 2, y: this.height - 2 }; }
  get bobRadius() { return CHARMS[this.charm].baseRadius * this.sizeScale; }
  get bobCenter() {
    const a = this.anchor;
    return {
      x: a.x + Math.sin(this.theta) * this.length,
      y: a.y - Math.cos(this.theta) * this.length,
    };
  }

  /// Pointer in the same y-up window space the physics uses.
  cursorInView() {
    if (!this.cursor) return null;
    return { x: this.cursor.x, y: this.height - this.cursor.y };
  }

  isOverCharm(pt, slack = 6) {
    if (!pt) return false;
    const b = this.bobCenter;
    return Math.hypot(pt.x - b.x, pt.y - b.y) <= this.bobRadius + slack;
  }

  step(nowMs) {
    if (!this.lastFrame) this.lastFrame = nowMs;
    const elapsed = Math.min((nowMs - this.lastFrame) / 1000, 0.1);
    this.lastFrame = nowMs;

    if (this.dropUntil !== null && nowMs >= this.dropUntil) {
      this.dropUntil = null;
      this.targetLength = Tuning.restLength;
    }

    // Mouse stirs the air. Impulse-based, so it stays outside the fixed step.
    const pt = this.cursorInView();
    if (!this.dragging && pt && this.prevCursor) {
      const dx = pt.x - this.prevCursor.x;
      const a = this.anchor;
      const dist = Math.hypot(pt.x - a.x, pt.y - a.y);
      const prox = Math.max(0, 1 - dist / 900);
      const drive = clamp(dx, -60, 60) * (Tuning.mouseDrive + Tuning.mouseDriveNear * prox);
      this.omega += drive / Math.max(this.length / 200, 0.5);
    }
    this.prevCursor = pt;

    const h = 1 / Tuning.stepHz;
    this.accumulator += elapsed;
    while (this.accumulator >= h) {
      this.integrate(h);
      this.accumulator -= h;
    }

    // tell the main process whether the pointer is on the charm
    const hit = this.dragging || this.isOverCharm(pt);
    if (hit !== this.wasHit) {
      this.wasHit = hit;
      this.onHitChange(hit);
    }
  }

  integrate(h) {
    this.time += h;
    this.length += (this.targetLength - this.length) * 0.10;

    if (this.dragging) return;

    this.omega += -(Tuning.gravity / Math.max(this.length, 40)) * Math.sin(this.theta) * h;
    this.omega += (Math.sin(this.time * 0.53) * 0.00035
                 + Math.sin(this.time * 0.17 + 1.3) * 0.0002) * Tuning.breeze;
    this.omega *= Tuning.damping;
    this.theta += this.omega * h;

    if (Math.abs(this.theta) > Tuning.maxAngle) {
      this.theta = this.theta > 0 ? Tuning.maxAngle : -Tuning.maxAngle;
      this.omega = -this.omega * 0.4;
    }
  }

  // MARK: interaction

  pointerDown(pt) {
    if (!this.isOverCharm(pt, 8)) return false;
    this.dragging = true;
    this.dragStarted = performance.now();
    this.dragMoved = 0;
    this.omega = 0;
    return true;
  }

  pointerMove(pt) {
    if (!this.dragging) return;
    const a = this.anchor;
    const dx = pt.x - a.x;
    const dy = Math.max(a.y - pt.y, 8);
    const newTheta = clamp(Math.atan2(dx, dy), -Tuning.maxAngle, Tuning.maxAngle);
    this.dragMoved += Math.abs(newTheta - this.theta) * 100;
    this.omega = (newTheta - this.theta) * Tuning.stepHz * 0.7;
    this.theta = newTheta;
    this.targetLength = clamp(Math.hypot(dx, dy),
                              Tuning.restLength * 0.7, Tuning.dropLength);
    this.length = this.targetLength;
  }

  pointerUp() {
    if (!this.dragging) return;
    this.dragging = false;
    if (this.dragMoved < 4 && performance.now() - this.dragStarted < 350) {
      this.toggleDrop();
    } else {
      this.targetLength = this.dropUntil === null ? Tuning.restLength : Tuning.dropLength;
    }
  }

  toggleDrop() {
    if (this.dropUntil === null) {
      this.dropUntil = performance.now() + Tuning.dropSeconds * 1000;
      this.targetLength = Tuning.dropLength;
      this.omega += 0.35;
    } else {
      this.dropUntil = null;
      this.targetLength = Tuning.restLength;
    }
  }

  // MARK: render

  render() {
    const ctx = this.ctx;
    const dpr = window.devicePixelRatio || 1;
    const w = this.width, h = this.height;

    if (this.canvas.width !== Math.round(w * dpr)) {
      this.canvas.width = Math.round(w * dpr);
      this.canvas.height = Math.round(h * dpr);
    }

    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    // flip to a y-up space so the ported drawing code reads like the original
    ctx.setTransform(dpr, 0, 0, -dpr, 0, h * dpr);

    const a = this.anchor;
    const b = this.bobCenter;
    const r = this.bobRadius;
    const dirX = Math.sin(this.theta), dirY = -Math.cos(this.theta);
    const endX = a.x + dirX * (this.length - r * 0.85);
    const endY = a.y + dirY * (this.length - r * 0.85);
    const energy = Math.min(1, Math.abs(this.omega) / 2.2);
    const shine = { time: this.time, energy, enabled: this.shimmer };

    // cord — dark core with a lit edge
    ctx.lineCap = 'round';
    ctx.strokeStyle = srgb(0.42, 0.31, 0.09);
    ctx.lineWidth = 2.6;
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(endX, endY);
    ctx.stroke();
    ctx.strokeStyle = srgb(0.93, 0.79, 0.40, 0.85);
    ctx.lineWidth = 1.0;
    ctx.beginPath();
    ctx.moveTo(a.x - 0.5, a.y);
    ctx.lineTo(endX - 0.5, endY);
    ctx.stroke();

    // beads
    const beads = [
      [0.60, r * 0.13, [[srgb(1, 1, 1), 0], [srgb(0.78, 0.80, 0.86), 1]]],
      [0.71, r * 0.19, [[srgb(0.42, 0.62, 1.00), 0], [srgb(0.05, 0.14, 0.60), 1]]],
      [0.82, r * 0.13, [[srgb(1, 1, 1), 0], [srgb(0.78, 0.80, 0.86), 1]]],
    ];
    for (const [t, rad, stops] of beads) {
      const px = a.x + (endX - a.x) * t, py = a.y + (endY - a.y) * t;
      fillRadial(ctx, (c) => ell(c, px - rad, py - rad, rad * 2, rad * 2),
        px - rad * 0.35, py + rad * 0.35, rad * 1.8, stops);
    }

    ctx.save();
    ctx.translate(b.x, b.y);
    ctx.rotate(-this.theta);
    drawCharm(ctx, this.charm, r, shine);
    ctx.restore();
  }
}
