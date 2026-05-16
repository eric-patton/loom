// Synthetic data-pipeline DSL for M6.2 — invented for the demo. Not a
// real package; demonstrates that the Loom kernel can model arbitrary
// constructor-tree DSLs beyond Flutter widgets and routing.

final pipeline = Pipeline(
  name: 'simple',
  steps: [
    ValidateInput(field: 'email', required: true),
    Transform(name: 'normalizeEmail'),
    SaveToDatabase(table: 'users'),
  ],
);
