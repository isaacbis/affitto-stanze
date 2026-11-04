'use strict';
// Test double: never contacts the real Firebase project.
function memoryFirestore() {
  const collections = new Map(); let serial = Promise.resolve(); let id = 0;
  function collection(name) {
    if (!collections.has(name)) collections.set(name, new Map());
    const data = collections.get(name);
    const doc = key => {
      key ??= `test-${++id}`;
      if (!key || key.includes('/')) throw Error('Invalid document ID');
      return { id: key, get: async () => ({ id: key, exists: data.has(key), data: () => data.get(key), ref: doc(key) }),
        set: async (value, options) => data.set(key, options?.merge ? {...data.get(key), ...value} : value),
        update: async value => { if (!data.has(key)) throw Error('Missing document'); data.set(key, {...data.get(key), ...value}); },
        delete: async () => data.delete(key) };
    };
    function query(filters = [], limit = Infinity) {
      return { where: (key, op, value) => query([...filters, [key, op, value]], limit), limit: value => query(filters, value),
        get: async () => {
          const docs = [...data].filter(([, value]) => filters.every(([key, op, expected]) => op === '==' ? value[key] === expected : op === '<' ? value[key] < expected : value[key] <= expected))
            .slice(0, limit).map(([key, value]) => ({ id: key, data: () => value, exists: true, ref: doc(key) }));
          return { docs, empty: !docs.length, size: docs.length };
        } };
    }
    return { ...query(), doc, add: async value => { const ref = doc(); await ref.set(value); return ref; } };
  }
  return { collection,
    runTransaction(fn) {
      const job = serial.then(async () => {
        const writes = []; const result = await fn({ get: ref => ref.get(), delete: ref => writes.push(() => ref.delete()), set: (ref, value) => writes.push(() => ref.set(value)) });
        for (const write of writes) await write(); return result;
      });
      serial = job.catch(() => {}); return job;
    }
  };
}
module.exports = { memoryFirestore };
