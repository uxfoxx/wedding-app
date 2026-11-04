-- Wording now records the faith it belongs to, so a Buddhist wedding is never offered Nikah
-- wording. event_kind is only the occasion (wedding, homecoming, engagement); the old
-- church/nikah/kovil kinds become a faith instead. seed_key lets the seed add new launch
-- wording without duplicating rows or restoring ones an admin edited.
ALTER TABLE wordings ADD COLUMN faith text CHECK (faith IN ('buddhist','hindu','muslim','christian'));
ALTER TABLE wordings ADD COLUMN seed_key text UNIQUE;

UPDATE wordings SET faith = 'christian', event_kind = 'wedding' WHERE event_kind = 'church';
UPDATE wordings SET faith = 'muslim', event_kind = 'wedding' WHERE event_kind = 'nikah';
UPDATE wordings SET faith = 'hindu', event_kind = 'wedding' WHERE event_kind = 'kovil';
-- The religious launch wording for a plain "wedding" is Buddhist (Triple Gem, තෙරුවන්).
UPDATE wordings SET faith = 'buddhist' WHERE tone = 'religious' AND event_kind = 'wedding' AND faith IS NULL;
