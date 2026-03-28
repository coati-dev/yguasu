/**
 * Toast notification module.
 * Appends a small toast to the document body for connect/disconnect events.
 *
 * Usage:
 *   import { showToast } from './toast.js'
 *   showToast('Launchkey 49 connected', 'connect')
 *   showToast('Launchkey 49 disconnected', 'disconnect')
 */

export function showToast(message, type = 'connect') {
  const toast = document.createElement('div')
  toast.className = `toast toast--${type}`
  toast.textContent = message

  document.body.appendChild(toast)

  // Trigger enter animation on next frame
  requestAnimationFrame(() => {
    requestAnimationFrame(() => toast.classList.add('toast--visible'))
  })

  setTimeout(() => {
    toast.classList.remove('toast--visible')
    toast.addEventListener('transitionend', () => toast.remove(), { once: true })
  }, 3000)
}
