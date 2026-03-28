/**
 * Synth module — piano-like tone using layered oscillators + ADSR envelope.
 * Velocity sensitive. Sustains while key is held, releases on note off.
 *
 * Usage:
 *   import { noteOn, noteOff } from './synth.js'
 *   noteOn(60, 100)   // middle C, velocity 100
 *   noteOff(60)
 */

const audioCtx = new (window.AudioContext || window.webkitAudioContext)()
const activeNodes = new Map() // midiNote → { gainNode, oscillators }

// MIDI note number → frequency in Hz
function midiToFreq(note) {
  return 440 * Math.pow(2, (note - 69) / 12)
}

// Map velocity (1–127) to gain (0.0–1.0) with a slight curve
function velocityToGain(velocity) {
  return Math.pow(velocity / 127, 1.4)
}

function createPianoOscillators(freq, ctx) {
  const oscillators = []

  // Fundamental — sine for the clean body
  const osc1 = ctx.createOscillator()
  osc1.type = 'sine'
  osc1.frequency.value = freq

  // 2nd harmonic — triangle adds warmth
  const osc2 = ctx.createOscillator()
  osc2.type = 'triangle'
  osc2.frequency.value = freq * 2

  // 3rd harmonic — very light, adds brightness
  const osc3 = ctx.createOscillator()
  osc3.type = 'sine'
  osc3.frequency.value = freq * 3

  oscillators.push(
    { osc: osc1, gainAmount: 1.0 },
    { osc: osc2, gainAmount: 0.35 },
    { osc: osc3, gainAmount: 0.08 },
  )

  return oscillators
}

export function noteOn(midiNote, velocity) {
  // Resume audio context if suspended (browser autoplay policy)
  if (audioCtx.state === 'suspended') audioCtx.resume()

  // If the note is already playing, stop it first
  if (activeNodes.has(midiNote)) noteOff(midiNote, true)

  const freq = midiToFreq(midiNote)
  const peakGain = velocityToGain(velocity)
  const now = audioCtx.currentTime

  // Master gain node for this note
  const masterGain = audioCtx.createGain()
  masterGain.connect(audioCtx.destination)

  // ADSR envelope — piano-like: fast attack, short decay to sustain, slow release
  masterGain.gain.setValueAtTime(0, now)
  masterGain.gain.linearRampToValueAtTime(peakGain, now + 0.005)       // attack
  masterGain.gain.exponentialRampToValueAtTime(peakGain * 0.7, now + 0.1) // decay
  // sustain held at ~70% of peak until noteOff

  const oscillators = createPianoOscillators(freq, audioCtx)

  oscillators.forEach(({ osc, gainAmount }) => {
    const oscGain = audioCtx.createGain()
    oscGain.gain.value = gainAmount
    osc.connect(oscGain)
    oscGain.connect(masterGain)
    osc.start(now)
  })

  activeNodes.set(midiNote, { masterGain, oscillators: oscillators.map((o) => o.osc) })
}

export function noteOff(midiNote, immediate = false) {
  const node = activeNodes.get(midiNote)
  if (!node) return

  const { masterGain, oscillators } = node
  const now = audioCtx.currentTime
  const releaseTime = immediate ? 0.01 : 0.4

  masterGain.gain.cancelScheduledValues(now)
  masterGain.gain.setValueAtTime(masterGain.gain.value, now)
  masterGain.gain.exponentialRampToValueAtTime(0.0001, now + releaseTime)

  oscillators.forEach((osc) => {
    try {
      osc.stop(now + releaseTime + 0.01)
    } catch (_) {}
  })

  activeNodes.delete(midiNote)
}
