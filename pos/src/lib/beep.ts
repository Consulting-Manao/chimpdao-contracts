let ctx: AudioContext | null = null;

/**
 * Short blip. Audio is a nicety on a payment terminal, so every failure mode
 * here is swallowed: a muted or blocked AudioContext must never break a sale.
 */
function beep(freq: number, ms: number, gain = 0.06): void {
  try {
    ctx ??= new AudioContext();
    void ctx.resume();
    const osc = ctx.createOscillator();
    const vol = ctx.createGain();
    osc.type = "sine";
    osc.frequency.value = freq;
    osc.connect(vol).connect(ctx.destination);
    const t = ctx.currentTime;
    vol.gain.setValueAtTime(gain, t);
    vol.gain.exponentialRampToValueAtTime(0.0001, t + ms / 1000);
    osc.start(t);
    osc.stop(t + ms / 1000);
  } catch {
    /* silent terminal is fine */
  }
}

export const cardBeep = () => beep(880, 70);
export const approvedBeep = () => {
  beep(1046, 70);
  setTimeout(() => beep(1568, 90), 80);
};
export const declinedBeep = () => beep(180, 220);
