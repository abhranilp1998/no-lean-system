import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/tell/domain/tell_classifier.dart';

void main() {
  TellKind k(String s) => classifyTell(s).kind;

  test('relapse', () {
    expect(k('I used again tonight'), TellKind.relapse);
    expect(k('had a bottle of ascoril 2 hours ago'), TellKind.relapse);
    expect(k('I relapsed'), TellKind.relapse);
    expect(classifyTell('drank lean an hour ago').hoursAgo, 1);
    expect(classifyTell('had 2 bottles 3 hours ago').hoursAgo, 3);
  });
  test('negation is not a relapse', () {
    expect(k("I didn't use today"), isNot(TellKind.relapse));
  });
  test('about to use', () {
    expect(k("I'm about to buy"), TellKind.aboutToUse);
    expect(k('craving so bad rn'), TellKind.aboutToUse);
    expect(k('gonna go get some'), TellKind.aboutToUse);
  });
  test('feedback', () {
    expect(k('the widget button is broken'), TellKind.feedback);
    expect(k('please add a dark mode setting'), TellKind.feedback);
  });
  test('use outranks feedback; ordinary text is other', () {
    expect(k('I used, and the app lock did not fire'), TellKind.relapse);
    expect(k('I had a long day at work'), TellKind.other);
    expect(k('took a walk'), TellKind.other);
    expect(k(''), TellKind.other);
  });
}
