const { collectVotesFromResult } = require('./utils');

test('returns zeros when no rows', () => {
  const result = collectVotesFromResult({ rows: [] });
  expect(result).toEqual({ a: 0, b: 0 });
});

test('counts votes for both options', () => {
  const result = collectVotesFromResult({
    rows: [
      { vote: 'a', count: '42' },
      { vote: 'b', count: '17' },
    ],
  });
  expect(result).toEqual({ a: 42, b: 17 });
});

test('handles partial results (only one option has votes)', () => {
  const result = collectVotesFromResult({
    rows: [{ vote: 'a', count: '5' }],
  });
  expect(result).toEqual({ a: 5, b: 0 });
});
