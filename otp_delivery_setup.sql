-- TezRider – OTP Delivery Proof Setup
-- Run this in Supabase SQL Editor BEFORE importing delivery_proof CSV

-- Add OTP column to orders (generated when rider accepts order)
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_otp TEXT;

-- Extend delivery_proof to store OTP verification details
ALTER TABLE public.delivery_proof
  ADD COLUMN IF NOT EXISTS otp         TEXT,
  ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP WITH TIME ZONE;

-- Optional: index for fast OTP lookup
CREATE INDEX IF NOT EXISTS idx_orders_delivery_otp
  ON public.orders (delivery_otp)
  WHERE delivery_otp IS NOT NULL;
