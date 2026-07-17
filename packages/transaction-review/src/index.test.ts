import { test } from "node:test";
import assert from "node:assert/strict";
import { PACKAGE_NAME } from "./index.ts";

test("package identity", () => {
  assert.equal(PACKAGE_NAME, "@tidyr/transaction-review");
});
