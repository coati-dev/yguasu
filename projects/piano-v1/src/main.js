import './style.css'
import { initMidi } from './midi.js'
import { noteOn, noteOff } from './synth.js'
import { createKeyboard } from './keyboard.js'
import { showToast } from './toast.js'

// --- DOM ---
const keyboardContainer = document.getElementById('keyboard-container')
const toggle49 = document.getElementById('toggle-49')
const toggle88 = document.getElementById('toggle-88')
const statusDot = document.getElementById('status-dot')
const statusText = document.getElementById('status-text')

// --- Keyboard ---
let currentMode = '49'
const keyboard = createKeyboard(keyboardContainer, currentMode)

function setActiveToggle(mode) {
  toggle49.classList.toggle('active', mode === '49')
  toggle88.classList.toggle('active', mode === '88')
}
setActiveToggle(currentMode)

toggle49.addEventListener('click', () => {
  currentMode = '49'
  keyboard.setMode('49')
  setActiveToggle('49')
})

toggle88.addEventListener('click', () => {
  currentMode = '88'
  keyboard.setMode('88')
  setActiveToggle('88')
})

// --- Status indicator ---
function setConnected(deviceName) {
  statusDot.classList.add('connected')
  statusText.textContent = deviceName
}

function setDisconnected() {
  statusDot.classList.remove('connected')
  statusText.textContent = 'No device detected'
}

// --- MIDI ---
initMidi({
  onNoteOn(midiNote, velocity) {
    noteOn(midiNote, velocity)
    keyboard.noteOn(midiNote)
  },
  onNoteOff(midiNote) {
    noteOff(midiNote)
    keyboard.noteOff(midiNote)
  },
  onConnect(deviceName) {
    setConnected(deviceName)
    showToast(`${deviceName} connected`, 'connect')
  },
  onDisconnect(deviceName) {
    setDisconnected()
    showToast(`${deviceName} disconnected`, 'disconnect')
  },
})
