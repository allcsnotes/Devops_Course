import './style.css'

const courses = [
  { title: 'DSA', price: 499 },
  { title: 'System Design', price: 499 },
  { title: 'Spring Boot', price: 499 },
  { title: 'GenAI', price: 499 },
  { title: 'DevOps', price: 499 },
]

document.querySelector('#app').innerHTML = `
  <h1>allcsvideos</h1>
  <ul>${courses.map(c => `<li>${c.title} - Rs ${c.price}</li>`).join('')}</ul>
`
