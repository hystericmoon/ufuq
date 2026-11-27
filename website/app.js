(() => {
  const shell = document.getElementById("notch-shell");
  const stateButtons = document.querySelectorAll(".seg-btn");
  const accentButtons = document.querySelectorAll(".dot");

  stateButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      stateButtons.forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      shell.dataset.state = btn.dataset.state;
    });
  });

  accentButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      accentButtons.forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      document.documentElement.style.setProperty("--accent", btn.dataset.accent);
    });
  });
})();
