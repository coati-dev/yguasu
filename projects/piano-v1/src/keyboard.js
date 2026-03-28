/**
 * Keyboard component — renders a piano keyboard into a container element.
 * Supports 49-key (Launchkey 49: C2–C6, MIDI 36–84) and 88-key (A0–C8, MIDI 21–108) modes.
 * Keys highlight on press and release on note off.
 * Uses percentage-based absolute positioning so it scales to any container width.
 *
 * Usage:
 *   import { createKeyboard } from './keyboard.js'
 *   const kb = createKeyboard(containerElement, '49')
 *   kb.noteOn(60)
 *   kb.noteOff(60)
 *   kb.setMode('88')
 */

const RANGES = {
  '49': { start: 36, end: 84 },  // C2–C6
  '88': { start: 21, end: 108 }, // A0–C8
}

const BLACK_SEMITONES = new Set([1, 3, 6, 8, 10])

function isBlack(midiNote) {
  return BLACK_SEMITONES.has(midiNote % 12)
}

/**
 * Count white keys from the start of the range up to (but not including) `note`.
 */
function countWhiteKeysBefore(note, rangeStart) {
  let count = 0
  for (let n = rangeStart; n < note; n++) {
    if (!isBlack(n)) count++
  }
  return count
}

function countWhiteKeysInRange(start, end) {
  let count = 0
  for (let n = start; n <= end; n++) {
    if (!isBlack(n)) count++
  }
  return count
}

export function createKeyboard(container, initialMode = '49') {
  let mode = initialMode
  let keyElements = new Map()

  function render() {
    container.innerHTML = ''
    keyElements.clear()

    const { start, end } = RANGES[mode]
    const totalWhite = countWhiteKeysInRange(start, end)
    const whiteWidthPct = 100 / totalWhite      // % width of one white key
    const blackWidthPct = whiteWidthPct * 0.58  // black keys are ~58% the width of white

    const wrapper = document.createElement('div')
    wrapper.className = 'keyboard-wrapper'

    // Render white keys first (z-index lower), black keys on top
    const whites = []
    const blacks = []

    for (let note = start; note <= end; note++) {
      const key = document.createElement('div')

      if (isBlack(note)) {
        // Black key: centered on the boundary between its two neighboring white keys
        const leftWhiteIndex = countWhiteKeysBefore(note, start)
        const leftPct = leftWhiteIndex * whiteWidthPct + (whiteWidthPct - blackWidthPct / 2) * 0.9

        key.className = 'key black'
        key.style.left = `${leftPct}%`
        key.style.width = `${blackWidthPct}%`
        blacks.push(key)
      } else {
        const whiteIndex = countWhiteKeysBefore(note, start)

        key.className = 'key white'
        key.style.left = `${whiteIndex * whiteWidthPct}%`
        key.style.width = `${whiteWidthPct}%`
        whites.push(key)
      }

      key.dataset.note = note
      keyElements.set(note, key)
    }

    // White keys first so black keys render on top
    whites.forEach((k) => wrapper.appendChild(k))
    blacks.forEach((k) => wrapper.appendChild(k))

    container.appendChild(wrapper)
  }

  function noteOn(midiNote) {
    keyElements.get(midiNote)?.classList.add('active')
  }

  function noteOff(midiNote) {
    keyElements.get(midiNote)?.classList.remove('active')
  }

  function setMode(newMode) {
    if (newMode === mode) return
    mode = newMode
    render()
  }

  render()
  return { noteOn, noteOff, setMode }
}
