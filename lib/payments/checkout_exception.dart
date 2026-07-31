/// A sanitized, user-safe failure raised by the checkout boundary.
///
/// These exceptions deliberately do not retain response bodies, request URLs,
/// payment-provider messages, or credentials. Detailed diagnostics belong in
/// server-side observability, not in the client error shown to a buyer.
sealed class CheckoutException implements Exception {
  final String code;
  final String publicMessage;
  final bool retryable;
  final int? statusCode;

  const CheckoutException({
    required this.code,
    required this.publicMessage,
    required this.retryable,
    this.statusCode,
  });

  @override
  String toString() => publicMessage;
}

final class CheckoutConfigurationException extends CheckoutException {
  const CheckoutConfigurationException()
    : super(
        code: 'checkout_not_configured',
        publicMessage: 'Secure checkout is not configured for this build.',
        retryable: false,
      );
}

final class CheckoutValidationException extends CheckoutException {
  const CheckoutValidationException([String? message])
    : super(
        code: 'invalid_checkout_data',
        publicMessage: message ?? 'The checkout details are not valid.',
        retryable: false,
      );
}

final class CheckoutAuthorizationException extends CheckoutException {
  const CheckoutAuthorizationException({required int statusCode})
    : super(
        code: 'checkout_authorization_required',
        publicMessage: 'Please sign in again before checking out.',
        retryable: false,
        statusCode: statusCode,
      );
}

final class CheckoutConflictException extends CheckoutException {
  const CheckoutConflictException()
    : super(
        code: 'checkout_inventory_conflict',
        publicMessage: 'One or more items are no longer available.',
        retryable: false,
        statusCode: 409,
      );
}

final class CheckoutSellerPayoutUnavailableException extends CheckoutException {
  const CheckoutSellerPayoutUnavailableException()
    : super(
        code: 'seller_payout_unavailable',
        publicMessage:
            'A seller is still setting up payouts. Remove that item or try again later.',
        retryable: false,
        statusCode: 409,
      );
}

final class CheckoutRejectedException extends CheckoutException {
  const CheckoutRejectedException({int statusCode = 422})
    : super(
        code: 'checkout_rejected',
        publicMessage: 'These checkout details could not be accepted.',
        retryable: false,
        statusCode: statusCode,
      );
}

final class CheckoutNotFoundException extends CheckoutException {
  const CheckoutNotFoundException()
    : super(
        code: 'checkout_not_found',
        publicMessage: 'This checkout could not be found or has expired.',
        retryable: false,
        statusCode: 404,
      );
}

final class CheckoutUnavailableException extends CheckoutException {
  const CheckoutUnavailableException({super.statusCode})
    : super(
        code: 'checkout_temporarily_unavailable',
        publicMessage: 'Secure checkout is temporarily unavailable. Try again.',
        retryable: true,
      );
}

final class CheckoutNetworkException extends CheckoutException {
  final bool timedOut;

  const CheckoutNetworkException({this.timedOut = false})
    : super(
        code: timedOut ? 'checkout_timeout' : 'checkout_network_error',
        publicMessage: timedOut
            ? 'Checkout took too long to respond. Try again.'
            : 'Could not reach secure checkout. Check your connection.',
        retryable: true,
      );
}

final class CheckoutProtocolException extends CheckoutException {
  const CheckoutProtocolException()
    : super(
        code: 'invalid_checkout_response',
        publicMessage: 'Checkout returned an invalid response. Try again.',
        retryable: true,
      );
}

final class CheckoutLaunchException extends CheckoutException {
  const CheckoutLaunchException({bool timedOut = false})
    : super(
        code: timedOut ? 'checkout_launch_timeout' : 'checkout_launch_failed',
        publicMessage: timedOut
            ? 'Opening secure checkout took too long. Try again.'
            : 'Secure checkout could not be opened. Try again.',
        retryable: true,
      );
}
