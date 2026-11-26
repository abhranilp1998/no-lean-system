import 'high_risk_dates.dart';

/// Offline festival calendar for an Indian 20–30 audience, 2026–2030.
///
/// Lunar festival days are listed explicitly (not computed). Sources used
/// while compiling: Government of India holiday lists, IMD Rashtriya
/// Panchanga, timeanddate, and public Indian holiday calendars. Eid dates
/// can move by a day with moon sighting; the user can add their own date
/// if a listed day is off.
///
/// Extend this table after 2030. Do not add a calculator.
const bundledFestivals = <BundledFestival>[
  BundledFestival(
    id: 'nye',
    name: "New Year's Eve",
    blurb: 'Late nights and parties.',
    dates: [
      '2026-12-31',
      '2027-12-31',
      '2028-12-31',
      '2029-12-31',
      '2030-12-31',
    ],
  ),
  BundledFestival(
    id: 'new_year',
    name: "New Year's Day",
    blurb: 'The morning after, and leftover plans.',
    dates: [
      '2026-01-01',
      '2027-01-01',
      '2028-01-01',
      '2029-01-01',
      '2030-01-01',
      '2031-01-01',
    ],
  ),
  BundledFestival(
    id: 'valentines',
    name: "Valentine's Day",
    blurb: 'Plans with a partner, or a hard night alone.',
    dates: [
      '2026-02-14',
      '2027-02-14',
      '2028-02-14',
      '2029-02-14',
      '2030-02-14',
    ],
  ),
  BundledFestival(
    id: 'shivaratri',
    name: 'Maha Shivaratri',
    blurb: 'An all-night festival for many households.',
    // Lunar. India / New Delhi.
    dates: [
      '2026-02-15',
      '2027-03-06',
      '2028-02-23',
      '2029-02-11',
      '2030-03-02',
    ],
  ),
  BundledFestival(
    id: 'holi',
    name: 'Holi',
    blurb: 'The colour day (Dhulandi).',
    // 2027 uses the Government of India list (23 Mar), not 22 Mar.
    dates: [
      '2026-03-04',
      '2027-03-23',
      '2028-03-11',
      '2029-03-01',
      '2030-03-20',
    ],
  ),
  BundledFestival(
    id: 'eid_fitr',
    name: 'Eid al-Fitr',
    blurb: 'Ramzan Id. May move a day with moon sighting.',
    dates: [
      '2026-03-21',
      '2027-03-10',
      '2028-02-27',
      '2029-02-15',
      '2030-02-05',
    ],
  ),
  BundledFestival(
    id: 'eid_adha',
    name: 'Eid al-Adha',
    blurb: 'Bakrid. May move a day with moon sighting.',
    // 2026 and 2028 follow Government / public-holiday lists
    // (27 May 2026, 5 May 2028) rather than tentative almanac days.
    dates: [
      '2026-05-27',
      '2027-05-17',
      '2028-05-05',
      '2029-04-25',
      '2030-04-14',
    ],
  ),
  BundledFestival(
    id: 'raksha_bandhan',
    name: 'Raksha Bandhan',
    blurb: 'Family gatherings.',
    dates: [
      '2026-08-28',
      '2027-08-17',
      '2028-08-05',
      '2029-08-23',
      '2030-08-13',
    ],
  ),
  BundledFestival(
    id: 'ganesh',
    name: 'Ganesh Chaturthi',
    blurb: 'The first day of the festival.',
    dates: [
      '2026-09-14',
      '2027-09-04',
      '2028-08-23',
      '2029-09-11',
      '2030-09-01',
    ],
  ),
  BundledFestival(
    id: 'durga_puja',
    name: 'Durga Puja',
    blurb: 'Maha Saptami, the start of the big days.',
    // span covers Saptami through Dashami when they fall across 3 days.
    spanDays: 3,
    dates: [
      '2026-10-18',
      '2027-10-06',
      '2028-09-25',
      '2029-10-13',
      '2030-10-03',
    ],
  ),
  BundledFestival(
    id: 'diwali',
    name: 'Diwali',
    blurb: 'Lakshmi Puja / the main night.',
    dates: [
      '2026-11-08',
      '2027-10-29',
      '2028-10-17',
      '2029-11-05',
      '2030-10-26',
    ],
  ),
  BundledFestival(
    id: 'christmas',
    name: 'Christmas',
    blurb: 'The 25th, and evening plans around it.',
    dates: [
      '2026-12-25',
      '2027-12-25',
      '2028-12-25',
      '2029-12-25',
      '2030-12-25',
    ],
  ),
];
