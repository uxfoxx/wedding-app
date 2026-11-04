-- Vendors buy featured placement (by the month) or the annual verified badge themselves.
-- months records what the payment bought, so a refund can take exactly that back.
ALTER TABLE payments ADD COLUMN months int;
CREATE INDEX ON payments (vendor_id);
