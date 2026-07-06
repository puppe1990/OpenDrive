const DEFAULT_MAX_CONCURRENT = 4;

export function createUploadScheduler({ maxConcurrent = DEFAULT_MAX_CONCURRENT, onRun }) {
  let active = 0;
  const waiting = [];

  const pump = () => {
    while (active < maxConcurrent && waiting.length > 0) {
      const entry = waiting.shift();
      active += 1;

      Promise.resolve(onRun(entry)).finally(() => {
        active -= 1;
        pump();
      });
    }
  };

  return {
    maxConcurrent,
    enqueue(entry) {
      waiting.push(entry);
      pump();
    },
    get activeCount() {
      return active;
    },
    get waitingCount() {
      return waiting.length;
    },
  };
}