import 'package:form_field_validator/form_field_validator.dart';

String? Function(String?)? requiredValidator({String? error}) {
  return RequiredValidator(errorText: error ?? 'This field is required*').call;
}

MultiValidator emailOrUsernameValidator() {
  return MultiValidator([
    RequiredValidator(errorText: 'Email / username is required'),
    MinLengthValidator(2, errorText: 'Enter a valid email or username'),
  ]);
}

MultiValidator passwordValidator() {
  return MultiValidator([
    RequiredValidator(errorText: 'Password is required'),
    MinLengthValidator(1, errorText: 'Password is required'),
  ]);
}
