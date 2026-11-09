JSON.stringify({
  title: document.title,
  url: location.href,
  textLength: document.body ? document.body.innerText.trim().length : -1,
  text: document.body ? document.body.innerText.trim().slice(0, 300) : '',
  ua: navigator.userAgent.slice(0, 80)
})
