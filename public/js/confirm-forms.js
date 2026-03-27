(() => {
  document.querySelectorAll('form[data-confirm]').forEach(form => {
    form.addEventListener('submit', event => {
      const message = form.getAttribute('data-confirm') || 'Sei sicuro?';

      if (!window.confirm(message)) {
        event.preventDefault();
      }
    });
  });
})();