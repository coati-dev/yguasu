/**
 * MIDI module — handles device detection, note on/off, and connect/disconnect events.
 *
 * Usage:
 *   import { initMidi } from './midi.js'
 *   initMidi({ onNoteOn, onNoteOff, onConnect, onDisconnect })
 */

let midiAccess = null
let connectedInput = null

function connectToFirstInput(inputs, callbacks) {
  for (const input of inputs.values()) {
    attachInput(input, callbacks)
    return
  }
}

function attachInput(input, { onNoteOn, onNoteOff, onConnect }) {
  if (connectedInput?.id === input.id) return
  connectedInput = input
  input.onmidimessage = (event) => handleMidiMessage(event, { onNoteOn, onNoteOff })
  onConnect?.(input.name)
}

function handleMidiMessage(event, { onNoteOn, onNoteOff }) {
  const [status, note, velocity] = event.data
  const command = status & 0xf0

  if (command === 0x90 && velocity > 0) {
    onNoteOn?.(note, velocity)
  } else if (command === 0x80 || (command === 0x90 && velocity === 0)) {
    onNoteOff?.(note)
  }
}

export async function initMidi({ onNoteOn, onNoteOff, onConnect, onDisconnect }) {
  if (!navigator.requestMIDIAccess) {
    console.warn('Web MIDI API not supported in this browser.')
    return
  }

  try {
    midiAccess = await navigator.requestMIDIAccess()
  } catch (err) {
    console.error('MIDI access denied:', err)
    return
  }

  connectToFirstInput(midiAccess.inputs, { onNoteOn, onNoteOff, onConnect })

  midiAccess.onstatechange = (event) => {
    const port = event.port
    if (port.type !== 'input') return

    if (port.state === 'connected') {
      attachInput(port, { onNoteOn, onNoteOff, onConnect })
    } else if (port.state === 'disconnected') {
      if (connectedInput?.id === port.id) {
        connectedInput = null
        onDisconnect?.(port.name)
        // Try to fall back to another available input
        connectToFirstInput(midiAccess.inputs, { onNoteOn, onNoteOff, onConnect })
      }
    }
  }
}
