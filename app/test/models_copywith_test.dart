import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';

/// `Entry.copyWith` uses a sentinel so a nullable field can distinguish
/// "leave this alone" from "set it to null". This is the file that would go
/// quietly wrong if the sentinel comparison were ever accidentally changed
/// from identity to equality, so it gets its own direct coverage rather than
/// only being exercised incidentally by the repository tests.
void main() {
  final base = const Entry(
    igdbId: 1,
    ownership: Ownership.owned,
    progress: Progress.playing,
    rating: 4,
    note: 'Great so far',
    recommendedBy: 'Priya',
    shelved: false,
  );

  test('omitting rating and note leaves both exactly as they were', () {
    final result = base.copyWith(progress: Progress.finished);
    expect(result.rating, 4);
    expect(result.note, 'Great so far');
  });

  test('passing an explicit null for rating clears it', () {
    final result = base.copyWith(rating: null);
    expect(result.rating, isNull);
    expect(result.note, 'Great so far', reason: 'note is untouched');
  });

  test('passing an explicit null for note clears it independently of rating',
      () {
    final result = base.copyWith(note: null);
    expect(result.note, isNull);
    expect(result.rating, 4, reason: 'rating is untouched');
  });

  test('setting a new rating value works alongside an unrelated field', () {
    final result = base.copyWith(rating: 5, shelved: true);
    expect(result.rating, 5);
    expect(result.shelved, isTrue);
    expect(result.note, 'Great so far');
  });

  test('fields with no copyWith parameter at all are always preserved', () {
    final result = base.copyWith(progress: Progress.finished);
    expect(result.igdbId, 1);
    expect(result.recommendedBy, 'Priya');
  });

  test('ownership and progress keep their original ?? behaviour', () {
    final result = base.copyWith();
    expect(result.ownership, Ownership.owned);
    expect(result.progress, Progress.playing);
  });
}
