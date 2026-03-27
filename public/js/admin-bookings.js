(() => {
  const adminRoomSelect = document.getElementById('adminRoomSelect');
  const adminBookingDate = document.getElementById('adminBookingDate');
  const adminSlotsContainer = document.getElementById('adminSlotsContainer');
  const adminStartHourInput = document.getElementById('adminStartHourInput');
  const adminEndHourInput = document.getElementById('adminEndHourInput');
  const adminSelectedStartText = document.getElementById('adminSelectedStartText');
  const adminSelectedEndText = document.getElementById('adminSelectedEndText');

  if (
    !adminRoomSelect ||
    !adminBookingDate ||
    !adminSlotsContainer ||
    !adminStartHourInput ||
    !adminEndHourInput ||
    !adminSelectedStartText ||
    !adminSelectedEndText
  ) {
    return;
  }

  let occupiedSlots = [];
  let selectedStart = null;
  let selectedEnd = null;

  function formatHour(value) {
    const numeric = Number(value);
    const hours = Math.floor(numeric);
    const minutes = numeric % 1 === 0.5 ? 30 : 0;
    return String(hours).padStart(2, '0') + ':' + String(minutes).padStart(2, '0');
  }

  function normalizeSlot(value) {
    return Number(Number(value).toFixed(1));
  }

  function resetSelection() {
    selectedStart = null;
    selectedEnd = null;
    adminStartHourInput.value = '';
    adminEndHourInput.value = '';
    adminSelectedStartText.textContent = '-';
    adminSelectedEndText.textContent = '-';
  }

  function refreshSelectedUI() {
    document.querySelectorAll('#adminSlotsContainer .slot-btn').forEach(btn => {
      btn.classList.remove('selected');
      const hour = Number(btn.dataset.hour);

      if (
        selectedStart !== null &&
        selectedEnd !== null &&
        hour >= selectedStart &&
        hour < selectedEnd
      ) {
        btn.classList.add('selected');
      }
    });

    adminSelectedStartText.textContent =
      selectedStart !== null ? formatHour(selectedStart) : '-';

    adminSelectedEndText.textContent =
      selectedEnd !== null ? formatHour(selectedEnd) : '-';
  }

  function handleSlotClick(hour) {
    hour = normalizeSlot(hour);

    if (selectedStart === null) {
      selectedStart = hour;
      selectedEnd = normalizeSlot(hour + 0.5);
    } else if (selectedStart !== null && selectedEnd !== null) {
      if (hour < selectedStart) {
        selectedStart = hour;
      } else {
        selectedEnd = normalizeSlot(hour + 0.5);
      }

      for (let h = selectedStart; h < selectedEnd; h += 0.5) {
        const current = normalizeSlot(h);

        if (occupiedSlots.includes(current)) {
          window.alert('Hai incluso una fascia occupata. Seleziona solo orari liberi consecutivi.');
          resetSelection();
          refreshSelectedUI();
          return;
        }
      }
    }

    adminStartHourInput.value = selectedStart;
    adminEndHourInput.value = selectedEnd;
    refreshSelectedUI();
  }

  function buildSlots() {
    adminSlotsContainer.innerHTML = '';

    for (let h = 8; h < 20.5; h += 0.5) {
      const slotValue = normalizeSlot(h);

      const slot = document.createElement('button');
      slot.type = 'button';
      slot.className = 'slot-btn';
      slot.dataset.hour = slotValue;
      slot.textContent = formatHour(slotValue);

      if (occupiedSlots.includes(slotValue)) {
        slot.classList.add('busy');
        slot.disabled = true;
      } else {
        slot.classList.add('free');
        slot.addEventListener('click', () => handleSlotClick(slotValue));
      }

      adminSlotsContainer.appendChild(slot);
    }

    refreshSelectedUI();
  }

  async function loadAvailability() {
    const roomId = adminRoomSelect.value;
    const date = adminBookingDate.value;

    resetSelection();
    adminSlotsContainer.innerHTML = '';

    if (!roomId || !date) return;

    try {
      const response = await fetch(
        `/admin/availability?room_id=${encodeURIComponent(roomId)}&booking_date=${encodeURIComponent(date)}`
      );

      if (!response.ok) {
        throw new Error('Errore risposta disponibilità admin');
      }

      const data = await response.json();
      occupiedSlots = (data.occupiedSlots || []).map(v => normalizeSlot(v));
      buildSlots();
    } catch (err) {
      console.error(err);
      adminSlotsContainer.innerHTML = '<p>Errore nel caricamento disponibilità</p>';
    }
  }

  adminRoomSelect.addEventListener('change', loadAvailability);
  adminBookingDate.addEventListener('change', loadAvailability);

  const today = new Date();
  const yyyy = today.getFullYear();
  const mm = String(today.getMonth() + 1).padStart(2, '0');
  const dd = String(today.getDate()).padStart(2, '0');
  const todayStr = `${yyyy}-${mm}-${dd}`;

  adminBookingDate.min = todayStr;
  adminBookingDate.value = todayStr;

  loadAvailability();
})();