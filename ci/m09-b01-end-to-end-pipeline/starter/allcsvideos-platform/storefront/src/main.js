import './style.css'

const app = document.querySelector('#app')
app.innerHTML = `
  <header><span class="logo">allcsvideos</span><span class="tag">video courses</span></header>
  <h2>Courses</h2>
  <section id="courses" class="grid"><p class="muted">Loading courses...</p></section>
  <h2>Ask Course Copilot</h2>
  <form id="ask"><input id="q" placeholder="What do you want to learn?" autocomplete="off" />
    <button>Ask</button></form>
  <p id="answer" class="muted"></p>
  <footer id="meta"></footer>
`

// the catalog comes from the API: storefront -> gateway -> catalog -> Redis / PostgreSQL
async function loadCourses() {
  const box = document.querySelector('#courses')
  try {
    const res = await fetch('/api/courses')
    const body = await res.json()
    if (!res.ok) throw new Error(body.message || `HTTP ${res.status}`)
    box.innerHTML = body.map(c => `
      <article class="card"><h3>${c.title}</h3>
        <p class="price">EUR ${c.priceEur}</p>
        <p class="muted">${c.seatsLeft} seats left</p></article>`).join('')
    document.querySelector('#meta').textContent =
      `${body.length} courses from the API, served by ${res.headers.get('X-Served-By')}`
  } catch (e) {
    // graceful error: the page stays up even when the catalog is down
    box.innerHTML = `<p class="error">${e.message}</p>`
  }
}

document.querySelector('#ask').addEventListener('submit', async (ev) => {
  ev.preventDefault()
  const out = document.querySelector('#answer')
  const q = document.querySelector('#q').value
  try {
    const res = await fetch(`/copilot/ask?q=${encodeURIComponent(q)}`)
    if (!res.ok) throw new Error()
    out.textContent = (await res.json()).answer
    out.className = 'answer'
  } catch {
    out.textContent = 'Course Copilot is not running right now.'
    out.className = 'error'
  }
})

loadCourses()
