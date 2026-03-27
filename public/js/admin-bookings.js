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

  const SLOT_START = 8;
  const SLOT_END = 20.5;
  const SLOT_STEP = 0.5;

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

  function getRomeNow() {
    const parts = new Intl.DateTimeFormat('sv-SE', {
      timeZone: 'Europe/Rome',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false
    }).formatToParts(new Date());

    const map = Object.fromEntries(
      parts
        .filter(part => part.type !== 'literal')
        .map(part => [part.type, part.value])
    );

    return {
      date: `${map.year}-${map.month}-${map.day}`,
      minutesNow:
        Number(map.hour) * 60 +
        Number(map.minute) +
        Number(map.second) / 60
    };
  }

  function isPastSlot(date, slotValue, nowRome) {
    return date === nowRome.date && slotValue * 60 <= nowRome.minutesNow;
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
      selectedEnd = normalizeSlot(hour + SLOT_STEP);
    } else if (selectedStart !== null && selectedEnd !== null) {
      if (hour < selectedStart) {
        selectedStart = hour;
      } else {
        selectedEnd = normalizeSlot(hour + SLOT_STEP);
      }

      for (let h = selectedStart; h < selectedEnd; h += SLOT_STEP) {
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
    const date = adminBookingDate.value;
    const nowRome = getRomeNow();

    for (let h = SLOT_START; h < SLOT_END; h += SLOT_STEP) {
      const slotValue = normalizeSlot(h);

      const slot = document.createElement('button');
      slot.type = 'button';
      slot.className = 'slot-btn';
      slot.dataset.hour = slotValue;
      slot.textContent = formatHour(slotValue);

      if (occupiedSlots.includes(slotValue)) {
        slot.classList.add('busy');
        slot.disabled = true;
      } else if (isPastSlot(date, slotValue, nowRome)) {
        slot.classList.add('busy', 'past');
        slot.disabled = true;
        slot.title = 'Orario già passato';
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

  const todayStr = getRomeNow().date;
  adminBookingDate.min = todayStr;
  adminBookingDate.value = todayStr;

  loadAvailability();
})();