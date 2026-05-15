// Synthetic pipeline with a conditional branch — exercises the
// `Branch` two-list-slot shape (onTrue / onFalse).

final pipeline = Pipeline(
  name: 'user-registration',
  steps: [
    ValidateInput(field: 'email', required: true),
    Transform(name: 'normalizeEmail'),
    Branch(
      condition: 'emailIsValid',
      onTrue: [
        SaveToDatabase(table: 'users'),
        SendEmail(template: 'welcome'),
      ],
      onFalse: [
        LogError(level: 'warn', message: 'Invalid email'),
      ],
    ),
    LogInfo(message: 'Pipeline complete'),
  ],
);
