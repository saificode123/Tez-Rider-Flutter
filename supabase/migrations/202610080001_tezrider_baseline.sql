-- TEST ONLY: schema-only baseline plus deny-by-default client containment.
-- Immutable source SHA256: 3b67b93133531794941a7148d744b0b215817e62f822bfda7e45a7b68d0c8f18
--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: account_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.account_status AS ENUM (
    'pending',
    'approved',
    'rejected'
);


--
-- Name: order_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.order_status AS ENUM (
    'pending',
    'processing',
    'ready',
    'out_for_delivery',
    'delivered',
    'cancelled'
);


--
-- Name: tailoring_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.tailoring_status AS ENUM (
    'pickup_requested',
    'picked_up',
    'at_tailor',
    'stitching',
    'ready',
    'out_for_delivery',
    'delivered'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'customer',
    'vendor',
    'rider',
    'admin'
);


--
-- Name: assign_available_rider(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_available_rider() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    target_rider_id TEXT;
BEGIN
    -- Search for the first available rider 
    -- In a full version, you would use st_distance with your gps_locations table
    SELECT userid INTO target_rider_id
    FROM public.riders
    WHERE isavailable = true 
      AND isverified = true
    LIMIT 1;

    -- If a rider is found, create the assignment
    IF target_rider_id IS NOT NULL THEN
        INSERT INTO public.rider_assignments (orderid, riderid, status, assignedat)
        VALUES (NEW.orderid, target_rider_id, 'Pending', NOW());
        
        -- Update the order table to show it's being assigned
        UPDATE public.orders 
        SET status = 'Rider Searching', 
            riderid = target_rider_id
        WHERE orderid = NEW.orderid;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: get_vendor_ratings(bigint[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_vendor_ratings(p_vendor_ids bigint[]) RETURNS TABLE(vendor_id bigint, avg_rating numeric, review_count bigint)
    LANGUAGE sql STABLE
    AS $$
  SELECT
    o.vendor_id,
    ROUND(AVG(r.rating)::numeric, 1) AS avg_rating,
    COUNT(r.id) AS review_count
  FROM public.reviews r
  JOIN public.orders o ON o.id = (r.order_id)::bigint
  WHERE o.vendor_id = ANY(p_vendor_ids)
  GROUP BY o.vendor_id;
$$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users 
    WHERE email = auth.jwt()->>'email' AND role = 'admin'
  );
$$;


--
-- Name: is_current_vendor(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_current_vendor(p_vendor_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    JOIN auth.users au
      ON au.id = auth.uid()
    WHERE u.id = p_vendor_id
      AND lower(trim(u.email)) = lower(trim(au.email))
      AND lower(trim(u.role)) = 'vendor'
  );
$$;


--
-- Name: notify_customer_on_order_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_customer_on_order_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  msg TEXT;
  ttl TEXT;
BEGIN
  IF NEW.order_status IS DISTINCT FROM OLD.order_status THEN
    CASE NEW.order_status
      WHEN 'accepted' THEN
        ttl := 'Order Accepted';
        msg := 'Your order has reached the vendor and is being prepared.';
      WHEN 'preparing' THEN
        ttl := 'Preparing your order';
        msg := 'The vendor is preparing your order.';
      WHEN 'ready' THEN
        ttl := 'Order Packed';
        msg := 'Your order is packed and waiting for a rider.';
      WHEN 'on_the_way' THEN
        ttl := 'Rider on the way';
        msg := 'A rider has picked up your order and is on the way.';
      WHEN 'delivered' THEN
        ttl := 'Order Delivered';
        msg := 'Your order has been delivered. Enjoy!';
      WHEN 'cancelled' THEN
        ttl := 'Order Cancelled';
        msg := 'Your order has been cancelled.';
      ELSE
        ttl := 'Order Update';
        msg := 'Your order status changed to ' || NEW.order_status || '.';
    END CASE;

    INSERT INTO public.notifications (user_id, title, message, type)
    VALUES (NEW.user_id, ttl, msg, 'order');
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: notify_new_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_new_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO notifications (user_id, title, body, type)
  VALUES (
    NEW.user_id,
    'Order Placed',
    'Your order has been placed successfully!',
    'order'
  );

  RETURN NEW;
END;
$$;


--
-- Name: notify_vendor_on_new_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_vendor_on_new_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO public.notifications (user_id, title, message, type)
  VALUES (
    NEW.vendor_id,
    'New Order Received',
    'You have a new order worth PKR ' || NEW.sub_total || '. Tap to view details.',
    'order'
  );
  RETURN NEW;
END;
$$;


--
-- Name: notify_vendor_on_status_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_vendor_on_status_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.notifications (user_id, title, message, type)
    VALUES (
      NEW.vendor_id,
      'Order Update',
      'Order #' || NEW.order_id || ' status changed to ' || NEW.status || '.',
      'order'
    );
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: sync_order_status_from_vendor_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_order_status_from_vendor_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    UPDATE public.orders
    SET order_status = NEW.status
    WHERE id = NEW.order_id;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: update_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: vendor_can_insert_product(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vendor_can_insert_product(p_vendor_id integer) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    JOIN auth.users au
      ON lower(trim(u.email)) = lower(trim(au.email))
    WHERE u.id = p_vendor_id
      AND lower(trim(u.role)) = 'vendor'
      AND au.id = auth.uid()
  );
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.addresses (
    id bigint NOT NULL,
    user_id bigint,
    label text NOT NULL,
    address text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.addresses ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.addresses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: admins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admins (
    id bigint NOT NULL,
    userid text,
    adminlevel integer,
    isverified boolean,
    permissions text,
    lastlogin timestamp with time zone,
    department text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: admins_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.admins_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admins_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admins_id_seq OWNED BY public.admins.id;


--
-- Name: analytics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.analytics (
    id bigint NOT NULL,
    dashboardid text,
    totalorders integer,
    revenue double precision,
    activeriders integer,
    lastlogin timestamp with time zone,
    topsellingproducts text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: analytics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.analytics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: analytics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.analytics_id_seq OWNED BY public.analytics.id;


--
-- Name: app_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_settings (
    id bigint NOT NULL,
    setting_key text NOT NULL,
    setting_value text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: app_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.app_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: app_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.app_settings_id_seq OWNED BY public.app_settings.id;


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id bigint NOT NULL,
    logid text,
    userid text,
    sessiontoken text,
    action text,
    module text,
    "timestamp" timestamp with time zone DEFAULT now()
);


--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: cart; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cart (
    id bigint NOT NULL,
    cartid text,
    customerid text,
    cartitems text,
    totalprice double precision,
    updatedat timestamp with time zone DEFAULT now()
);


--
-- Name: cart_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cart_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cart_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cart_id_seq OWNED BY public.cart.id;


--
-- Name: cart_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cart_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    product_id text NOT NULL,
    name text NOT NULL,
    price integer NOT NULL,
    quantity integer DEFAULT 1,
    image text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT cart_items_price_check CHECK ((price >= 0)),
    CONSTRAINT cart_items_quantity_check CHECK ((quantity > 0))
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id bigint NOT NULL,
    name text NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now(),
    image_url text,
    icon text,
    sort_order integer DEFAULT 0
);


--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;


--
-- Name: chat_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_messages (
    id bigint NOT NULL,
    room_id bigint,
    sender_id bigint,
    message text,
    image_url text,
    is_read boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: chat_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.chat_messages ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.chat_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: chat_participants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_participants (
    room_id bigint NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: chat_rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_rooms (
    id bigint NOT NULL,
    user1_id bigint,
    user2_id bigint,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: chat_rooms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.chat_rooms ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.chat_rooms_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: complaints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.complaints (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    order_id bigint,
    type text NOT NULL,
    description text NOT NULL,
    status text DEFAULT 'open'::text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: customer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer (
    id bigint NOT NULL,
    user_id bigint,
    name text,
    phone text,
    address text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: customer_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.customer ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.customer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id bigint NOT NULL,
    user_id bigint,
    name text,
    phone text,
    city text,
    address text,
    order_count integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.customers ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.customers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: delivery_proof; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delivery_proof (
    id bigint NOT NULL,
    proofid text,
    orderid text,
    riderid text,
    photourl text,
    location text,
    "timestamp" timestamp with time zone DEFAULT now(),
    otpconfirmed boolean,
    otp text,
    is_verified boolean DEFAULT false,
    verified_at timestamp with time zone
);


--
-- Name: delivery_proof_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.delivery_proof_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: delivery_proof_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.delivery_proof_id_seq OWNED BY public.delivery_proof.id;


--
-- Name: disputes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.disputes (
    id bigint NOT NULL,
    type text NOT NULL,
    by text,
    status text DEFAULT 'Open'::text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: disputes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.disputes ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.disputes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: favorites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.favorites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    favorite_user_id uuid,
    type text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: favourite; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.favourite (
    id bigint NOT NULL,
    user_id bigint,
    product_id bigint,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: favourite_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.favourite ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.favourite_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: feedback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feedback (
    id bigint NOT NULL,
    feedbackid text,
    orderid text,
    customerid text,
    rating integer,
    comment text,
    targetid text,
    targettype text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: feedback_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.feedback_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: feedback_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.feedback_id_seq OWNED BY public.feedback.id;


--
-- Name: gifts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gifts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sender_id uuid,
    recipient_name text NOT NULL,
    recipient_address text NOT NULL,
    message text,
    occasion text DEFAULT 'Birthday'::text,
    gift_item_id text,
    gift_item_name text,
    amount integer DEFAULT 0,
    status text DEFAULT 'pending'::text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT gifts_amount_check CHECK ((amount >= 0))
);


--
-- Name: gps_locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gps_locations (
    id bigint NOT NULL,
    rider_id text NOT NULL,
    latitude numeric NOT NULL,
    longitude numeric NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: gps_locations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.gps_locations ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.gps_locations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id bigint NOT NULL,
    room_id bigint,
    sender_id bigint,
    text text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.messages ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id bigint NOT NULL,
    user_id bigint,
    title text NOT NULL,
    message text NOT NULL,
    type text DEFAULT 'system'::text,
    is_read boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.notifications ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_items (
    id bigint NOT NULL,
    vendor_order_id bigint,
    product_id bigint,
    quantity integer DEFAULT 1,
    price_at_time numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: order_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.order_items ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.order_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id bigint NOT NULL,
    user_id bigint,
    vendor_id bigint,
    rider_id bigint,
    amount numeric DEFAULT 0 NOT NULL,
    fare numeric DEFAULT 0,
    order_status text DEFAULT 'placed'::text,
    payment_method text DEFAULT 'COD'::text,
    delivery_address text,
    delivery_lat numeric,
    delivery_lng numeric,
    is_gift boolean DEFAULT false,
    recipient_name text,
    recipient_phone text,
    gift_message text,
    created_at timestamp with time zone DEFAULT now(),
    delivery_otp text,
    has_prescription_items boolean DEFAULT false,
    prescription_status text DEFAULT 'none'::text,
    delivery_speed text DEFAULT 'standard'::text
);


--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.orders ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: payment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment (
    id bigint NOT NULL,
    order_id bigint,
    amount numeric DEFAULT 0 NOT NULL,
    method text DEFAULT 'COD'::text,
    status text DEFAULT 'Pending'::text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: payment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.payment ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.payment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id bigint NOT NULL,
    paymentid text,
    orderid text,
    customerid text,
    method text,
    status text,
    amount double precision,
    invoiceurl text,
    paidat timestamp with time zone
);


--
-- Name: payments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payments_id_seq OWNED BY public.payments.id;


--
-- Name: prescription_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prescription_items (
    id bigint NOT NULL,
    vendor_order_id bigint NOT NULL,
    product_id bigint NOT NULL,
    requires_verification boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: prescription_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.prescription_items ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.prescription_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: prescriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prescriptions (
    id integer NOT NULL,
    vendor_order_id integer NOT NULL,
    customer_id integer NOT NULL,
    vendor_id integer NOT NULL,
    prescription_image_url text NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying,
    vendor_notes text,
    uploaded_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    reviewed_at timestamp without time zone,
    reviewed_by integer,
    CONSTRAINT prescriptions_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying])::text[])))
);


--
-- Name: prescriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.prescriptions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.prescriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: product_recommendations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_recommendations (
    id bigint NOT NULL,
    product_id bigint NOT NULL,
    complementary_product_id bigint NOT NULL,
    category_tag text,
    priority integer DEFAULT 1,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: product_recommendations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.product_recommendations ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.product_recommendations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id bigint NOT NULL,
    vendor_id bigint,
    category text DEFAULT 'General'::text,
    name text NOT NULL,
    description text,
    price numeric DEFAULT 0 NOT NULL,
    image_url text,
    is_available boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    requires_prescription boolean DEFAULT false
);


--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.products ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: review; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.review (
    id bigint NOT NULL,
    product_id bigint,
    user_id bigint,
    rating integer DEFAULT 5,
    comment text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: review_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.review ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.review_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id bigint,
    reviewer_id uuid,
    reviewee_id uuid,
    rating integer,
    comment text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT reviews_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);


--
-- Name: rider_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rider_assignments (
    id bigint NOT NULL,
    assignid bigint,
    riderid bigint,
    orderid bigint,
    status text DEFAULT 'Pending'::text
);


--
-- Name: rider_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.rider_assignments ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.rider_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: riders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.riders (
    id bigint NOT NULL,
    userid bigint,
    is_available boolean DEFAULT true,
    latitude numeric,
    longitude numeric,
    isavailable boolean DEFAULT true
);


--
-- Name: riders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.riders ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.riders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: stores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stores (
    id bigint NOT NULL,
    vendor_id bigint,
    name text NOT NULL,
    address text NOT NULL,
    latitude numeric,
    longitude numeric
);


--
-- Name: stores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.stores ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.stores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tailoring_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tailoring_requests (
    id bigint NOT NULL,
    vendor_id bigint,
    customer_id bigint,
    instructions text,
    status text DEFAULT 'pending'::text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: tailoring_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.tailoring_requests ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tailoring_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    name text NOT NULL,
    email text NOT NULL,
    phone text,
    role text DEFAULT 'customer'::text,
    verification_status text DEFAULT 'approved'::text,
    profile_image text,
    created_at timestamp with time zone DEFAULT now(),
    cnic text,
    cnic_image_url text,
    rejection_reason text
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.users ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: vendor_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vendor_orders (
    id bigint NOT NULL,
    order_id bigint,
    vendor_id bigint,
    sub_total numeric DEFAULT 0 NOT NULL,
    status text DEFAULT 'pending'::text,
    created_at timestamp with time zone DEFAULT now(),
    prescription_id bigint,
    requires_prescription boolean DEFAULT false
);


--
-- Name: vendor_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.vendor_orders ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.vendor_orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: vendors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vendors (
    id bigint NOT NULL,
    user_id bigint,
    store_name text NOT NULL,
    is_active boolean DEFAULT true,
    latitude numeric,
    longitude numeric,
    address text
);


--
-- Name: vendors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.vendors ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.vendors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: admins id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admins ALTER COLUMN id SET DEFAULT nextval('public.admins_id_seq'::regclass);


--
-- Name: analytics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analytics ALTER COLUMN id SET DEFAULT nextval('public.analytics_id_seq'::regclass);


--
-- Name: app_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_settings ALTER COLUMN id SET DEFAULT nextval('public.app_settings_id_seq'::regclass);


--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: cart id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cart ALTER COLUMN id SET DEFAULT nextval('public.cart_id_seq'::regclass);


--
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);


--
-- Name: delivery_proof id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_proof ALTER COLUMN id SET DEFAULT nextval('public.delivery_proof_id_seq'::regclass);


--
-- Name: feedback id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback ALTER COLUMN id SET DEFAULT nextval('public.feedback_id_seq'::regclass);


--
-- Name: payments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments ALTER COLUMN id SET DEFAULT nextval('public.payments_id_seq'::regclass);


--
-- Name: addresses addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.addresses
    ADD CONSTRAINT addresses_pkey PRIMARY KEY (id);


--
-- Name: admins admins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admins
    ADD CONSTRAINT admins_pkey PRIMARY KEY (id);


--
-- Name: analytics analytics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analytics
    ADD CONSTRAINT analytics_pkey PRIMARY KEY (id);


--
-- Name: app_settings app_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_settings
    ADD CONSTRAINT app_settings_pkey PRIMARY KEY (id);


--
-- Name: app_settings app_settings_setting_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_settings
    ADD CONSTRAINT app_settings_setting_key_key UNIQUE (setting_key);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: cart_items cart_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_pkey PRIMARY KEY (id);


--
-- Name: cart cart_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cart
    ADD CONSTRAINT cart_pkey PRIMARY KEY (id);


--
-- Name: categories categories_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_name_key UNIQUE (name);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: chat_messages chat_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (id);


--
-- Name: chat_participants chat_participants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_participants
    ADD CONSTRAINT chat_participants_pkey PRIMARY KEY (room_id, user_id);


--
-- Name: chat_rooms chat_rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_rooms
    ADD CONSTRAINT chat_rooms_pkey PRIMARY KEY (id);


--
-- Name: complaints complaints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_pkey PRIMARY KEY (id);


--
-- Name: customer customer_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer
    ADD CONSTRAINT customer_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: delivery_proof delivery_proof_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_proof
    ADD CONSTRAINT delivery_proof_pkey PRIMARY KEY (id);


--
-- Name: disputes disputes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disputes
    ADD CONSTRAINT disputes_pkey PRIMARY KEY (id);


--
-- Name: favorites favorites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_pkey PRIMARY KEY (id);


--
-- Name: favorites favorites_user_id_favorite_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_user_id_favorite_user_id_key UNIQUE (user_id, favorite_user_id);


--
-- Name: favourite favourite_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favourite
    ADD CONSTRAINT favourite_pkey PRIMARY KEY (id);


--
-- Name: feedback feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_pkey PRIMARY KEY (id);


--
-- Name: gifts gifts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gifts
    ADD CONSTRAINT gifts_pkey PRIMARY KEY (id);


--
-- Name: gps_locations gps_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gps_locations
    ADD CONSTRAINT gps_locations_pkey PRIMARY KEY (id);


--
-- Name: gps_locations gps_locations_rider_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gps_locations
    ADD CONSTRAINT gps_locations_rider_id_key UNIQUE (rider_id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: payment payment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: prescription_items prescription_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prescription_items
    ADD CONSTRAINT prescription_items_pkey PRIMARY KEY (id);


--
-- Name: prescriptions prescriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prescriptions
    ADD CONSTRAINT prescriptions_pkey PRIMARY KEY (id);


--
-- Name: product_recommendations product_recommendations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_recommendations
    ADD CONSTRAINT product_recommendations_pkey PRIMARY KEY (id);


--
-- Name: product_recommendations product_recommendations_product_id_complementary_product_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_recommendations
    ADD CONSTRAINT product_recommendations_product_id_complementary_product_id_key UNIQUE (product_id, complementary_product_id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: review review_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review
    ADD CONSTRAINT review_pkey PRIMARY KEY (id);


--
-- Name: reviews reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);


--
-- Name: rider_assignments rider_assignments_assignid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rider_assignments
    ADD CONSTRAINT rider_assignments_assignid_key UNIQUE (assignid);


--
-- Name: rider_assignments rider_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rider_assignments
    ADD CONSTRAINT rider_assignments_pkey PRIMARY KEY (id);


--
-- Name: riders riders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.riders
    ADD CONSTRAINT riders_pkey PRIMARY KEY (id);


--
-- Name: stores stores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_pkey PRIMARY KEY (id);


--
-- Name: tailoring_requests tailoring_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tailoring_requests
    ADD CONSTRAINT tailoring_requests_pkey PRIMARY KEY (id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: vendor_orders vendor_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vendor_orders
    ADD CONSTRAINT vendor_orders_pkey PRIMARY KEY (id);


--
-- Name: vendors vendors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vendors
    ADD CONSTRAINT vendors_pkey PRIMARY KEY (id);


--
-- Name: vendors vendors_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vendors
    ADD CONSTRAINT vendors_user_id_key UNIQUE (user_id);


--
-- Name: idx_cart_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cart_user_id ON public.cart_items USING btree (user_id);


--
-- Name: idx_complaints_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_complaints_user_id ON public.complaints USING btree (user_id);


--
-- Name: idx_gifts_sender_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gifts_sender_id ON public.gifts USING btree (sender_id);


--
-- Name: idx_orders_delivery_otp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_delivery_otp ON public.orders USING btree (delivery_otp) WHERE (delivery_otp IS NOT NULL);


--
-- Name: idx_prescription_items_vendor_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_prescription_items_vendor_order_id ON public.prescription_items USING btree (vendor_order_id);


--
-- Name: idx_prescriptions_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_prescriptions_customer_id ON public.prescriptions USING btree (customer_id);


--
-- Name: idx_prescriptions_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_prescriptions_status ON public.prescriptions USING btree (status);


--
-- Name: idx_prescriptions_vendor_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_prescriptions_vendor_order_id ON public.prescriptions USING btree (vendor_order_id);


--
-- Name: idx_product_recommendations_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_recommendations_product_id ON public.product_recommendations USING btree (product_id);


--
-- Name: orders trg_notify_customer_order_status; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_customer_order_status AFTER UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.notify_customer_on_order_status();


--
-- Name: vendor_orders trg_notify_vendor_new_order; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_vendor_new_order AFTER INSERT ON public.vendor_orders FOR EACH ROW EXECUTE FUNCTION public.notify_vendor_on_new_order();


--
-- Name: vendor_orders trg_notify_vendor_status_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_vendor_status_change AFTER UPDATE ON public.vendor_orders FOR EACH ROW EXECUTE FUNCTION public.notify_vendor_on_status_change();


--
-- Name: vendor_orders trg_sync_order_status; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_order_status AFTER UPDATE ON public.vendor_orders FOR EACH ROW EXECUTE FUNCTION public.sync_order_status_from_vendor_order();


--
-- Name: addresses addresses_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.addresses
    ADD CONSTRAINT addresses_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: chat_rooms chat_rooms_user1_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_rooms
    ADD CONSTRAINT chat_rooms_user1_id_fkey FOREIGN KEY (user1_id) REFERENCES public.users(id);


--
-- Name: chat_rooms chat_rooms_user2_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_rooms
    ADD CONSTRAINT chat_rooms_user2_id_fkey FOREIGN KEY (user2_id) REFERENCES public.users(id);


--
-- Name: customer customer_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer
    ADD CONSTRAINT customer_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: customers customers_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: favourite favourite_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favourite
    ADD CONSTRAINT favourite_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: favourite favourite_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favourite
    ADD CONSTRAINT favourite_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: messages messages_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.chat_rooms(id) ON DELETE CASCADE;


--
-- Name: messages messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;


--
-- Name: order_items order_items_vendor_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_vendor_order_id_fkey FOREIGN KEY (vendor_order_id) REFERENCES public.vendor_orders(id) ON DELETE CASCADE;


--
-- Name: orders orders_rider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_rider_id_fkey FOREIGN KEY (rider_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: orders orders_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: orders orders_vendor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: payment payment_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: prescription_items prescription_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prescription_items
    ADD CONSTRAINT prescription_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;


--
-- Name: prescription_items prescription_items_vendor_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prescription_items
    ADD CONSTRAINT prescription_items_vendor_order_id_fkey FOREIGN KEY (vendor_order_id) REFERENCES public.vendor_orders(id) ON DELETE CASCADE;


--
-- Name: product_recommendations product_recommendations_complementary_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_recommendations
    ADD CONSTRAINT product_recommendations_complementary_product_id_fkey FOREIGN KEY (complementary_product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: product_recommendations product_recommendations_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_recommendations
    ADD CONSTRAINT product_recommendations_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: products products_vendor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: review review_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review
    ADD CONSTRAINT review_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: review review_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review
    ADD CONSTRAINT review_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: rider_assignments rider_assignments_orderid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rider_assignments
    ADD CONSTRAINT rider_assignments_orderid_fkey FOREIGN KEY (orderid) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: rider_assignments rider_assignments_riderid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rider_assignments
    ADD CONSTRAINT rider_assignments_riderid_fkey FOREIGN KEY (riderid) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: riders riders_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.riders
    ADD CONSTRAINT riders_userid_fkey FOREIGN KEY (userid) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: stores stores_vendor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tailoring_requests tailoring_requests_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tailoring_requests
    ADD CONSTRAINT tailoring_requests_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tailoring_requests tailoring_requests_vendor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tailoring_requests
    ADD CONSTRAINT tailoring_requests_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: vendor_orders vendor_orders_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vendor_orders
    ADD CONSTRAINT vendor_orders_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: vendor_orders vendor_orders_prescription_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vendor_orders
    ADD CONSTRAINT vendor_orders_prescription_id_fkey FOREIGN KEY (prescription_id) REFERENCES public.prescriptions(id) ON DELETE SET NULL;


--
-- Name: vendor_orders vendor_orders_vendor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vendor_orders
    ADD CONSTRAINT vendor_orders_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: vendors vendors_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vendors
    ADD CONSTRAINT vendors_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: users Allow authenticated insert users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated insert users" ON public.users FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: users Allow authenticated select users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated select users" ON public.users FOR SELECT TO authenticated USING (true);


--
-- Name: users Allow authenticated update users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated update users" ON public.users FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: categories Anyone can read categories; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone can read categories" ON public.categories FOR SELECT USING (true);


--
-- Name: prescriptions Customers can view their own prescriptions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Customers can view their own prescriptions" ON public.prescriptions FOR SELECT USING ((((auth.uid())::text = (customer_id)::text) OR ((auth.uid())::text = (reviewed_by)::text)));


--
-- Name: prescriptions Vendors can view prescriptions for their orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Vendors can view prescriptions for their orders" ON public.prescriptions FOR SELECT USING ((vendor_order_id IN ( SELECT vo.id
   FROM public.vendor_orders vo
  WHERE (vo.vendor_id = ( SELECT users.id
           FROM public.users
          WHERE (users.email = (auth.jwt() ->> 'email'::text)))))));


--
-- Name: addresses addr_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addr_delete ON public.addresses FOR DELETE TO authenticated USING (true);


--
-- Name: addresses addr_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addr_insert ON public.addresses FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: addresses addr_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addr_read ON public.addresses FOR SELECT TO authenticated USING (true);


--
-- Name: addresses addr_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addr_update ON public.addresses FOR UPDATE TO authenticated USING (true);


--
-- Name: addresses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;

--
-- Name: analytics; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.analytics ENABLE ROW LEVEL SECURITY;

--
-- Name: app_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: app_settings app_settings_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY app_settings_read ON public.app_settings FOR SELECT USING (true);


--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: cart; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cart ENABLE ROW LEVEL SECURITY;

--
-- Name: cart_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;

--
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- Name: categories categories_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_read ON public.categories FOR SELECT USING (true);


--
-- Name: chat_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_messages chat_msg_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY chat_msg_insert ON public.chat_messages FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: chat_messages chat_msg_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY chat_msg_read ON public.chat_messages FOR SELECT TO authenticated USING (true);


--
-- Name: chat_participants chat_part_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY chat_part_insert ON public.chat_participants FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: chat_participants chat_part_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY chat_part_read ON public.chat_participants FOR SELECT TO authenticated USING (true);


--
-- Name: chat_participants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_rooms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.chat_rooms ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_rooms chat_rooms_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY chat_rooms_insert ON public.chat_rooms FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: chat_rooms chat_rooms_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY chat_rooms_read ON public.chat_rooms FOR SELECT TO authenticated USING (true);


--
-- Name: complaints; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;

--
-- Name: products customers_can_view_available_products; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customers_can_view_available_products ON public.products FOR SELECT TO authenticated USING ((is_available = true));


--
-- Name: delivery_proof; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.delivery_proof ENABLE ROW LEVEL SECURITY;

--
-- Name: disputes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.disputes ENABLE ROW LEVEL SECURITY;

--
-- Name: disputes disputes_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY disputes_insert ON public.disputes FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: disputes disputes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY disputes_select ON public.disputes FOR SELECT TO authenticated USING (true);


--
-- Name: disputes disputes_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY disputes_update ON public.disputes FOR UPDATE TO authenticated USING (true);


--
-- Name: favourite fav_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fav_delete ON public.favourite FOR DELETE TO authenticated USING (true);


--
-- Name: favourite fav_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fav_insert ON public.favourite FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: favourite fav_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fav_read ON public.favourite FOR SELECT TO authenticated USING (true);


--
-- Name: favorites; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;

--
-- Name: favourite; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.favourite ENABLE ROW LEVEL SECURITY;

--
-- Name: feedback; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

--
-- Name: gifts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gifts ENABLE ROW LEVEL SECURITY;

--
-- Name: gps_locations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gps_locations ENABLE ROW LEVEL SECURITY;

--
-- Name: gps_locations gps_locations_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gps_locations_insert ON public.gps_locations FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: gps_locations gps_locations_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gps_locations_select ON public.gps_locations FOR SELECT TO authenticated USING (true);


--
-- Name: gps_locations gps_locations_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gps_locations_update ON public.gps_locations FOR UPDATE TO authenticated USING (true);


--
-- Name: messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: messages messages_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY messages_insert ON public.messages FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: messages messages_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY messages_select ON public.messages FOR SELECT TO authenticated USING (true);


--
-- Name: notifications notif_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notif_insert ON public.notifications FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: notifications notif_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notif_read ON public.notifications FOR SELECT TO authenticated USING (true);


--
-- Name: notifications notif_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notif_update ON public.notifications FOR UPDATE TO authenticated USING (true);


--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: order_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

--
-- Name: order_items order_items_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY order_items_insert ON public.order_items FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: order_items order_items_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY order_items_select ON public.order_items FOR SELECT TO authenticated USING (true);


--
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- Name: orders orders_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_insert ON public.orders FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: orders orders_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_select ON public.orders FOR SELECT TO authenticated USING (true);


--
-- Name: orders orders_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_update ON public.orders FOR UPDATE TO authenticated USING (true);


--
-- Name: payment; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment ENABLE ROW LEVEL SECURITY;

--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: prescription_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.prescription_items ENABLE ROW LEVEL SECURITY;

--
-- Name: prescriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.prescriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: product_recommendations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_recommendations ENABLE ROW LEVEL SECURITY;

--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: products products_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_delete ON public.products FOR DELETE TO authenticated USING (true);


--
-- Name: products products_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_insert ON public.products FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: products products_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_read ON public.products FOR SELECT TO authenticated USING (true);


--
-- Name: products products_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_update ON public.products FOR UPDATE TO authenticated USING (true);


--
-- Name: review; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.review ENABLE ROW LEVEL SECURITY;

--
-- Name: reviews; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

--
-- Name: rider_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rider_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: rider_assignments rider_assignments_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rider_assignments_insert ON public.rider_assignments FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: rider_assignments rider_assignments_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rider_assignments_select ON public.rider_assignments FOR SELECT TO authenticated USING (true);


--
-- Name: rider_assignments rider_assignments_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rider_assignments_update ON public.rider_assignments FOR UPDATE TO authenticated USING (true);


--
-- Name: riders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.riders ENABLE ROW LEVEL SECURITY;

--
-- Name: riders riders_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY riders_insert ON public.riders FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: riders riders_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY riders_select ON public.riders FOR SELECT TO authenticated USING (true);


--
-- Name: riders riders_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY riders_update ON public.riders FOR UPDATE TO authenticated USING (true);


--
-- Name: stores; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;

--
-- Name: stores stores_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stores_insert ON public.stores FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: stores stores_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stores_read ON public.stores FOR SELECT USING (true);


--
-- Name: stores stores_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stores_select ON public.stores FOR SELECT TO authenticated USING (true);


--
-- Name: stores stores_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stores_update ON public.stores FOR UPDATE TO authenticated USING (true);


--
-- Name: tailoring_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tailoring_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: tailoring_requests tailoring_requests_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tailoring_requests_insert ON public.tailoring_requests FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: tailoring_requests tailoring_requests_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tailoring_requests_select ON public.tailoring_requests FOR SELECT TO authenticated USING (true);


--
-- Name: tailoring_requests tailoring_requests_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tailoring_requests_update ON public.tailoring_requests FOR UPDATE TO authenticated USING (true);


--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: users users_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_read ON public.users FOR SELECT TO authenticated USING (true);


--
-- Name: products vendor_delete_own_products; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vendor_delete_own_products ON public.products FOR DELETE TO authenticated USING (public.is_current_vendor(vendor_id));


--
-- Name: products vendor_insert_own_products; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vendor_insert_own_products ON public.products FOR INSERT TO authenticated WITH CHECK (public.is_current_vendor(vendor_id));


--
-- Name: vendor_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.vendor_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: vendor_orders vendor_orders_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vendor_orders_insert ON public.vendor_orders FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: vendor_orders vendor_orders_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vendor_orders_select ON public.vendor_orders FOR SELECT TO authenticated USING (true);


--
-- Name: vendor_orders vendor_orders_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vendor_orders_update ON public.vendor_orders FOR UPDATE TO authenticated USING (true);


--
-- Name: products vendor_select_own_products; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vendor_select_own_products ON public.products FOR SELECT TO authenticated USING (public.is_current_vendor(vendor_id));


--
-- Name: products vendor_update_own_products; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vendor_update_own_products ON public.products FOR UPDATE TO authenticated USING (public.is_current_vendor(vendor_id)) WITH CHECK (public.is_current_vendor(vendor_id));


--
-- Name: vendors; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;

--
-- Name: vendors vendors_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vendors_insert ON public.vendors FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: vendors vendors_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vendors_read ON public.vendors FOR SELECT USING (true);


--
-- Name: vendors vendors_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vendors_select ON public.vendors FOR SELECT TO authenticated USING (true);


--
-- Name: vendors vendors_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vendors_update ON public.vendors FOR UPDATE TO authenticated USING (true);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION assign_available_rider(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.assign_available_rider() TO anon;
GRANT ALL ON FUNCTION public.assign_available_rider() TO authenticated;
GRANT ALL ON FUNCTION public.assign_available_rider() TO service_role;


--
-- Name: FUNCTION get_vendor_ratings(p_vendor_ids bigint[]); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_vendor_ratings(p_vendor_ids bigint[]) TO anon;
GRANT ALL ON FUNCTION public.get_vendor_ratings(p_vendor_ids bigint[]) TO authenticated;
GRANT ALL ON FUNCTION public.get_vendor_ratings(p_vendor_ids bigint[]) TO service_role;


--
-- Name: FUNCTION is_admin(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.is_admin() TO anon;
GRANT ALL ON FUNCTION public.is_admin() TO authenticated;
GRANT ALL ON FUNCTION public.is_admin() TO service_role;


--
-- Name: FUNCTION is_current_vendor(p_vendor_id bigint); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.is_current_vendor(p_vendor_id bigint) TO anon;
GRANT ALL ON FUNCTION public.is_current_vendor(p_vendor_id bigint) TO authenticated;
GRANT ALL ON FUNCTION public.is_current_vendor(p_vendor_id bigint) TO service_role;


--
-- Name: FUNCTION notify_customer_on_order_status(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.notify_customer_on_order_status() TO anon;
GRANT ALL ON FUNCTION public.notify_customer_on_order_status() TO authenticated;
GRANT ALL ON FUNCTION public.notify_customer_on_order_status() TO service_role;


--
-- Name: FUNCTION notify_new_order(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.notify_new_order() TO anon;
GRANT ALL ON FUNCTION public.notify_new_order() TO authenticated;
GRANT ALL ON FUNCTION public.notify_new_order() TO service_role;


--
-- Name: FUNCTION notify_vendor_on_new_order(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.notify_vendor_on_new_order() TO anon;
GRANT ALL ON FUNCTION public.notify_vendor_on_new_order() TO authenticated;
GRANT ALL ON FUNCTION public.notify_vendor_on_new_order() TO service_role;


--
-- Name: FUNCTION notify_vendor_on_status_change(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.notify_vendor_on_status_change() TO anon;
GRANT ALL ON FUNCTION public.notify_vendor_on_status_change() TO authenticated;
GRANT ALL ON FUNCTION public.notify_vendor_on_status_change() TO service_role;


--
-- Name: FUNCTION sync_order_status_from_vendor_order(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sync_order_status_from_vendor_order() TO anon;
GRANT ALL ON FUNCTION public.sync_order_status_from_vendor_order() TO authenticated;
GRANT ALL ON FUNCTION public.sync_order_status_from_vendor_order() TO service_role;


--
-- Name: FUNCTION update_timestamp(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.update_timestamp() TO anon;
GRANT ALL ON FUNCTION public.update_timestamp() TO authenticated;
GRANT ALL ON FUNCTION public.update_timestamp() TO service_role;


--
-- Name: FUNCTION vendor_can_insert_product(p_vendor_id integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.vendor_can_insert_product(p_vendor_id integer) TO anon;
GRANT ALL ON FUNCTION public.vendor_can_insert_product(p_vendor_id integer) TO authenticated;
GRANT ALL ON FUNCTION public.vendor_can_insert_product(p_vendor_id integer) TO service_role;


--
-- Name: TABLE addresses; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.addresses TO anon;
GRANT ALL ON TABLE public.addresses TO authenticated;
GRANT ALL ON TABLE public.addresses TO service_role;


--
-- Name: SEQUENCE addresses_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.addresses_id_seq TO anon;
GRANT ALL ON SEQUENCE public.addresses_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.addresses_id_seq TO service_role;


--
-- Name: TABLE admins; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.admins TO anon;
GRANT ALL ON TABLE public.admins TO authenticated;
GRANT ALL ON TABLE public.admins TO service_role;


--
-- Name: SEQUENCE admins_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.admins_id_seq TO anon;
GRANT ALL ON SEQUENCE public.admins_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.admins_id_seq TO service_role;


--
-- Name: TABLE analytics; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.analytics TO anon;
GRANT ALL ON TABLE public.analytics TO authenticated;
GRANT ALL ON TABLE public.analytics TO service_role;


--
-- Name: SEQUENCE analytics_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.analytics_id_seq TO anon;
GRANT ALL ON SEQUENCE public.analytics_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.analytics_id_seq TO service_role;


--
-- Name: TABLE app_settings; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.app_settings TO anon;
GRANT ALL ON TABLE public.app_settings TO authenticated;
GRANT ALL ON TABLE public.app_settings TO service_role;


--
-- Name: SEQUENCE app_settings_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.app_settings_id_seq TO anon;
GRANT ALL ON SEQUENCE public.app_settings_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.app_settings_id_seq TO service_role;


--
-- Name: TABLE audit_logs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.audit_logs TO anon;
GRANT ALL ON TABLE public.audit_logs TO authenticated;
GRANT ALL ON TABLE public.audit_logs TO service_role;


--
-- Name: SEQUENCE audit_logs_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.audit_logs_id_seq TO anon;
GRANT ALL ON SEQUENCE public.audit_logs_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.audit_logs_id_seq TO service_role;


--
-- Name: TABLE cart; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cart TO anon;
GRANT ALL ON TABLE public.cart TO authenticated;
GRANT ALL ON TABLE public.cart TO service_role;


--
-- Name: SEQUENCE cart_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.cart_id_seq TO anon;
GRANT ALL ON SEQUENCE public.cart_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.cart_id_seq TO service_role;


--
-- Name: TABLE cart_items; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cart_items TO anon;
GRANT ALL ON TABLE public.cart_items TO authenticated;
GRANT ALL ON TABLE public.cart_items TO service_role;


--
-- Name: TABLE categories; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.categories TO anon;
GRANT ALL ON TABLE public.categories TO authenticated;
GRANT ALL ON TABLE public.categories TO service_role;


--
-- Name: SEQUENCE categories_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.categories_id_seq TO anon;
GRANT ALL ON SEQUENCE public.categories_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.categories_id_seq TO service_role;


--
-- Name: TABLE chat_messages; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.chat_messages TO anon;
GRANT ALL ON TABLE public.chat_messages TO authenticated;
GRANT ALL ON TABLE public.chat_messages TO service_role;


--
-- Name: SEQUENCE chat_messages_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.chat_messages_id_seq TO anon;
GRANT ALL ON SEQUENCE public.chat_messages_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.chat_messages_id_seq TO service_role;


--
-- Name: TABLE chat_participants; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.chat_participants TO anon;
GRANT ALL ON TABLE public.chat_participants TO authenticated;
GRANT ALL ON TABLE public.chat_participants TO service_role;


--
-- Name: TABLE chat_rooms; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.chat_rooms TO anon;
GRANT ALL ON TABLE public.chat_rooms TO authenticated;
GRANT ALL ON TABLE public.chat_rooms TO service_role;


--
-- Name: SEQUENCE chat_rooms_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.chat_rooms_id_seq TO anon;
GRANT ALL ON SEQUENCE public.chat_rooms_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.chat_rooms_id_seq TO service_role;


--
-- Name: TABLE complaints; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.complaints TO anon;
GRANT ALL ON TABLE public.complaints TO authenticated;
GRANT ALL ON TABLE public.complaints TO service_role;


--
-- Name: TABLE customer; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.customer TO anon;
GRANT ALL ON TABLE public.customer TO authenticated;
GRANT ALL ON TABLE public.customer TO service_role;


--
-- Name: SEQUENCE customer_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.customer_id_seq TO anon;
GRANT ALL ON SEQUENCE public.customer_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.customer_id_seq TO service_role;


--
-- Name: TABLE customers; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.customers TO anon;
GRANT ALL ON TABLE public.customers TO authenticated;
GRANT ALL ON TABLE public.customers TO service_role;


--
-- Name: SEQUENCE customers_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.customers_id_seq TO anon;
GRANT ALL ON SEQUENCE public.customers_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.customers_id_seq TO service_role;


--
-- Name: TABLE delivery_proof; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.delivery_proof TO anon;
GRANT ALL ON TABLE public.delivery_proof TO authenticated;
GRANT ALL ON TABLE public.delivery_proof TO service_role;


--
-- Name: SEQUENCE delivery_proof_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.delivery_proof_id_seq TO anon;
GRANT ALL ON SEQUENCE public.delivery_proof_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.delivery_proof_id_seq TO service_role;


--
-- Name: TABLE disputes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.disputes TO anon;
GRANT ALL ON TABLE public.disputes TO authenticated;
GRANT ALL ON TABLE public.disputes TO service_role;


--
-- Name: SEQUENCE disputes_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.disputes_id_seq TO anon;
GRANT ALL ON SEQUENCE public.disputes_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.disputes_id_seq TO service_role;


--
-- Name: TABLE favorites; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.favorites TO anon;
GRANT ALL ON TABLE public.favorites TO authenticated;
GRANT ALL ON TABLE public.favorites TO service_role;


--
-- Name: TABLE favourite; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.favourite TO anon;
GRANT ALL ON TABLE public.favourite TO authenticated;
GRANT ALL ON TABLE public.favourite TO service_role;


--
-- Name: SEQUENCE favourite_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.favourite_id_seq TO anon;
GRANT ALL ON SEQUENCE public.favourite_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.favourite_id_seq TO service_role;


--
-- Name: TABLE feedback; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.feedback TO anon;
GRANT ALL ON TABLE public.feedback TO authenticated;
GRANT ALL ON TABLE public.feedback TO service_role;


--
-- Name: SEQUENCE feedback_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.feedback_id_seq TO anon;
GRANT ALL ON SEQUENCE public.feedback_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.feedback_id_seq TO service_role;


--
-- Name: TABLE gifts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.gifts TO anon;
GRANT ALL ON TABLE public.gifts TO authenticated;
GRANT ALL ON TABLE public.gifts TO service_role;


--
-- Name: TABLE gps_locations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.gps_locations TO anon;
GRANT ALL ON TABLE public.gps_locations TO authenticated;
GRANT ALL ON TABLE public.gps_locations TO service_role;


--
-- Name: SEQUENCE gps_locations_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.gps_locations_id_seq TO anon;
GRANT ALL ON SEQUENCE public.gps_locations_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.gps_locations_id_seq TO service_role;


--
-- Name: TABLE messages; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.messages TO anon;
GRANT ALL ON TABLE public.messages TO authenticated;
GRANT ALL ON TABLE public.messages TO service_role;


--
-- Name: SEQUENCE messages_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.messages_id_seq TO anon;
GRANT ALL ON SEQUENCE public.messages_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.messages_id_seq TO service_role;


--
-- Name: TABLE notifications; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.notifications TO anon;
GRANT ALL ON TABLE public.notifications TO authenticated;
GRANT ALL ON TABLE public.notifications TO service_role;


--
-- Name: SEQUENCE notifications_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.notifications_id_seq TO anon;
GRANT ALL ON SEQUENCE public.notifications_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.notifications_id_seq TO service_role;


--
-- Name: TABLE order_items; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.order_items TO anon;
GRANT ALL ON TABLE public.order_items TO authenticated;
GRANT ALL ON TABLE public.order_items TO service_role;


--
-- Name: SEQUENCE order_items_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.order_items_id_seq TO anon;
GRANT ALL ON SEQUENCE public.order_items_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.order_items_id_seq TO service_role;


--
-- Name: TABLE orders; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.orders TO anon;
GRANT ALL ON TABLE public.orders TO authenticated;
GRANT ALL ON TABLE public.orders TO service_role;


--
-- Name: SEQUENCE orders_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.orders_id_seq TO anon;
GRANT ALL ON SEQUENCE public.orders_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.orders_id_seq TO service_role;


--
-- Name: TABLE payment; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.payment TO anon;
GRANT ALL ON TABLE public.payment TO authenticated;
GRANT ALL ON TABLE public.payment TO service_role;


--
-- Name: SEQUENCE payment_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.payment_id_seq TO anon;
GRANT ALL ON SEQUENCE public.payment_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.payment_id_seq TO service_role;


--
-- Name: TABLE payments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.payments TO anon;
GRANT ALL ON TABLE public.payments TO authenticated;
GRANT ALL ON TABLE public.payments TO service_role;


--
-- Name: SEQUENCE payments_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.payments_id_seq TO anon;
GRANT ALL ON SEQUENCE public.payments_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.payments_id_seq TO service_role;


--
-- Name: TABLE prescription_items; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.prescription_items TO anon;
GRANT ALL ON TABLE public.prescription_items TO authenticated;
GRANT ALL ON TABLE public.prescription_items TO service_role;


--
-- Name: SEQUENCE prescription_items_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.prescription_items_id_seq TO anon;
GRANT ALL ON SEQUENCE public.prescription_items_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.prescription_items_id_seq TO service_role;


--
-- Name: TABLE prescriptions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.prescriptions TO anon;
GRANT ALL ON TABLE public.prescriptions TO authenticated;
GRANT ALL ON TABLE public.prescriptions TO service_role;


--
-- Name: SEQUENCE prescriptions_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.prescriptions_id_seq TO anon;
GRANT ALL ON SEQUENCE public.prescriptions_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.prescriptions_id_seq TO service_role;


--
-- Name: TABLE product_recommendations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.product_recommendations TO anon;
GRANT ALL ON TABLE public.product_recommendations TO authenticated;
GRANT ALL ON TABLE public.product_recommendations TO service_role;


--
-- Name: SEQUENCE product_recommendations_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.product_recommendations_id_seq TO anon;
GRANT ALL ON SEQUENCE public.product_recommendations_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.product_recommendations_id_seq TO service_role;


--
-- Name: TABLE products; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.products TO anon;
GRANT ALL ON TABLE public.products TO authenticated;
GRANT ALL ON TABLE public.products TO service_role;


--
-- Name: SEQUENCE products_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.products_id_seq TO anon;
GRANT ALL ON SEQUENCE public.products_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.products_id_seq TO service_role;


--
-- Name: TABLE review; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.review TO anon;
GRANT ALL ON TABLE public.review TO authenticated;
GRANT ALL ON TABLE public.review TO service_role;


--
-- Name: SEQUENCE review_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.review_id_seq TO anon;
GRANT ALL ON SEQUENCE public.review_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.review_id_seq TO service_role;


--
-- Name: TABLE reviews; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.reviews TO anon;
GRANT ALL ON TABLE public.reviews TO authenticated;
GRANT ALL ON TABLE public.reviews TO service_role;


--
-- Name: TABLE rider_assignments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.rider_assignments TO anon;
GRANT ALL ON TABLE public.rider_assignments TO authenticated;
GRANT ALL ON TABLE public.rider_assignments TO service_role;


--
-- Name: SEQUENCE rider_assignments_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.rider_assignments_id_seq TO anon;
GRANT ALL ON SEQUENCE public.rider_assignments_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.rider_assignments_id_seq TO service_role;


--
-- Name: TABLE riders; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.riders TO anon;
GRANT ALL ON TABLE public.riders TO authenticated;
GRANT ALL ON TABLE public.riders TO service_role;


--
-- Name: SEQUENCE riders_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.riders_id_seq TO anon;
GRANT ALL ON SEQUENCE public.riders_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.riders_id_seq TO service_role;


--
-- Name: TABLE stores; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.stores TO anon;
GRANT ALL ON TABLE public.stores TO authenticated;
GRANT ALL ON TABLE public.stores TO service_role;


--
-- Name: SEQUENCE stores_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.stores_id_seq TO anon;
GRANT ALL ON SEQUENCE public.stores_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.stores_id_seq TO service_role;


--
-- Name: TABLE tailoring_requests; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tailoring_requests TO anon;
GRANT ALL ON TABLE public.tailoring_requests TO authenticated;
GRANT ALL ON TABLE public.tailoring_requests TO service_role;


--
-- Name: SEQUENCE tailoring_requests_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.tailoring_requests_id_seq TO anon;
GRANT ALL ON SEQUENCE public.tailoring_requests_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.tailoring_requests_id_seq TO service_role;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.users TO anon;
GRANT ALL ON TABLE public.users TO authenticated;
GRANT ALL ON TABLE public.users TO service_role;


--
-- Name: SEQUENCE users_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.users_id_seq TO anon;
GRANT ALL ON SEQUENCE public.users_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.users_id_seq TO service_role;


--
-- Name: TABLE vendor_orders; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vendor_orders TO anon;
GRANT ALL ON TABLE public.vendor_orders TO authenticated;
GRANT ALL ON TABLE public.vendor_orders TO service_role;


--
-- Name: SEQUENCE vendor_orders_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.vendor_orders_id_seq TO anon;
GRANT ALL ON SEQUENCE public.vendor_orders_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.vendor_orders_id_seq TO service_role;


--
-- Name: TABLE vendors; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vendors TO anon;
GRANT ALL ON TABLE public.vendors TO authenticated;
GRANT ALL ON TABLE public.vendors TO service_role;


--
-- Name: SEQUENCE vendors_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.vendors_id_seq TO anon;
GRANT ALL ON SEQUENCE public.vendors_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.vendors_id_seq TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--



--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--



--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--



--
-- PostgreSQL database dump complete
--



-- TEST containment is part of the same baseline migration transaction. Never
-- expose the legacy ALL grants before the reviewed FR-21 policies are applied.
do $$ declare t record; begin
  for t in select tablename from pg_tables where schemaname='public' loop
    execute format('alter table public.%I enable row level security',t.tablename);
  end loop;
end $$;
revoke all on all tables in schema public from public,anon,authenticated;
revoke all on all sequences in schema public from public,anon,authenticated;
revoke all on all functions in schema public from public,anon,authenticated;
revoke create on schema public from public,anon,authenticated;
grant usage on schema public to authenticated;
alter default privileges for role postgres in schema public revoke all on tables from anon,authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon,authenticated;
alter default privileges for role postgres in schema public revoke all on functions from anon,authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from public;
