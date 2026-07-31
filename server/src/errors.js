export class AppError extends Error {
  constructor(status, code, message, details = undefined, retryable = false) {
    super(message);
    this.name = 'AppError';
    this.status = status;
    this.code = code;
    this.details = details;
    this.retryable = retryable;
  }
}

export function asAppError(error) {
  if (error instanceof AppError) return error;
  return new AppError(
    500,
    'internal_error',
    'The checkout service could not complete the request.',
    undefined,
    true,
  );
}
