import 'dart:async';

/// Fixed diagnostic stages. Raw exceptions and protocol frames never reach UI.
enum TransferDiagnosticStage {
  validating,
  localProfile,
  connecting,
  requesting,
  waitingForApproval,
  verifying,
  committing,
  recovering,
  installing,
  activating,
  publishing,
}

enum TransferFailureCode {
  existingProfile,
  candidateConflict,
  secureStorage,
  candidateInvalid,
  invalidInput,
  timeout,
  connection,
  responseRejected,
  verification,
  localPreparation,
  interrupted,
}

class TransferFailure {
  const TransferFailure(this.code, this.stage);

  final TransferFailureCode code;
  final TransferDiagnosticStage stage;

  String get diagnosticCode =>
      'DT_${code.name.toUpperCase()}_${stage.name.toUpperCase()}';
}

TransferFailure classifyTransferFailure(
  Object error,
  TransferDiagnosticStage stage,
) {
  TransferFailureCode? code;
  if (error is StateError) {
    code = switch (error.message) {
      'Existing local profile identity is protected' =>
        TransferFailureCode.existingProfile,
      'Existing candidate trust anchor differs' =>
        TransferFailureCode.candidateConflict,
      'Secure candidate read failed' ||
      'Secure candidate persistence failed; resume before retry' =>
        TransferFailureCode.secureStorage,
      'Sealed candidate invalid; preserve it for recovery' =>
        TransferFailureCode.candidateInvalid,
      'Invalid transfer endpoint or credentials' =>
        TransferFailureCode.invalidInput,
      'Unexpected transfer response' => TransferFailureCode.responseRejected,
      'Candidate challenge differs' ||
      'Approval not bound to current request' ||
      'Invalid transition signature' ||
      'Invalid proof envelope' ||
      'Invalid proof' => TransferFailureCode.verification,
      _ => null,
    };
  }
  code ??= error is TimeoutException
      ? TransferFailureCode.timeout
      : switch (stage) {
          TransferDiagnosticStage.connecting => TransferFailureCode.connection,
          TransferDiagnosticStage.localProfile =>
            TransferFailureCode.localPreparation,
          TransferDiagnosticStage.verifying =>
            TransferFailureCode.verification,
          _ => TransferFailureCode.interrupted,
        };
  return TransferFailure(code, stage);
}
