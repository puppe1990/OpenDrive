import assert from "node:assert/strict";
import test from "node:test";

import { createUploadScheduler } from "../../assets/js/upload_scheduler.js";

test("runs at most maxConcurrent uploads at once", async () => {
  let active = 0;
  let maxActive = 0;
  let started = 0;
  const releaseResolvers = [];

  const scheduler = createUploadScheduler({
    maxConcurrent: 2,
    onRun: () =>
      new Promise((resolve) => {
        started += 1;
        active += 1;
        maxActive = Math.max(maxActive, active);
        releaseResolvers.push(() => {
          active -= 1;
          resolve();
        });
      }),
  });

  scheduler.enqueue("a");
  scheduler.enqueue("b");
  scheduler.enqueue("c");

  await new Promise((resolve) => setTimeout(resolve, 10));

  assert.equal(maxActive, 2);
  assert.equal(started, 2);
  assert.equal(scheduler.waitingCount, 1);

  releaseResolvers.shift()();
  await new Promise((resolve) => setTimeout(resolve, 10));

  assert.equal(started, 3);
  assert.equal(maxActive, 2);
  assert.equal(releaseResolvers.length, 2);

  while (releaseResolvers.length > 0) {
    releaseResolvers.shift()();
  }

  await new Promise((resolve) => setTimeout(resolve, 10));

  assert.equal(active, 0);
  assert.equal(scheduler.activeCount, 0);
  assert.equal(scheduler.waitingCount, 0);
});

test("defaults maxConcurrent to four", () => {
  const scheduler = createUploadScheduler({ onRun: async () => {} });
  assert.equal(scheduler.maxConcurrent, 4);
});