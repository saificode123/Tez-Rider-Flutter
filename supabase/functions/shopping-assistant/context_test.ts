import {assistantContext, plainAssistantText, responseFault} from './context.ts';
function ok(value: unknown): asserts value { if (!value) throw Error('Assertion failed'); }
Deno.test('wrong currency is rejected', () => { ok(responseFault('Price: ₹80')); });
Deno.test('physical receipt promise is rejected', () => { ok(responseFault('The rider will give you a receipt.')); });
Deno.test('correct digital invoice guidance is retained', () => {
  ok(responseFault('Pay PKR 80 in cash. Your invoice is in Order History.') === null);
});
Deno.test('plain response removes markdown wrappers without changing Urdu or prices', () => {
  ok(plainAssistantText('## Price\n**PKR 80**\n**نقد ادائیگی**') === 'Price\nPKR 80\nنقد ادائیگی');
});
Deno.test('explicit order projects only approved fields', async () => {
  const context = await assistantContext('Where is order 42?', async (name, params) => {
    ok(name === 'final2_order_detail' && params.p_order_id === 42);
    return {code: 'OK', order_id: 42, status: 'pending', address: 'PRIVATE', phone: 'PRIVATE', rider_id: 8};
  });
  ok(JSON.stringify(context.order) === '{"order_id":42,"status":"pending"}');
  ok(!JSON.stringify(context).includes('PRIVATE'));
});
Deno.test('Urdu order number reaches ownership RPC', async () => {
  await assistantContext('آرڈر ۴۲ کہاں ہے؟', async (_, params) => {
    ok(params.p_order_id === 42); return {code: 'OK', order_id: 42, status: 'pending'};
  });
});
Deno.test('latest explicit order supersedes history', async () => {
  await assistantContext('order 42\norder 51', async (_, params) => {
    ok(params.p_order_id === 51); return {code: 'OK', order_id: 51, status: 'pending'};
  });
});
Deno.test('unauthorized and nonexistent orders indistinguishable', async () => {
  const context = await assistantContext('order 999', async () => { throw Error('private details'); });
  ok(!context.order && typeof context.orders_error === 'string');
  ok(!JSON.stringify(context).includes('private details'));
});
Deno.test('ambiguous question uses at most five owned statuses', async () => {
  const context = await assistantContext('Where is my order?', async (name) => {
    ok(name === 'fr25_order_history');
    return Array.from({length: 30}, (_, id) => ({id, order_status: 'pending', address: 'PRIVATE'}));
  });
  ok((context.recent_owned_orders as unknown[]).length === 5);
  ok(!JSON.stringify(context).includes('PRIVATE'));
});
Deno.test('catalogue projection and sample limits are explicit', async () => {
  const context = await assistantContext('Find available products', async (name, params) => {
    ok(name === 'final2_catalog' && params.p_limit === 20);
    return {items: [{id: 1, name: 'Rice', price: 50, stock_qty: 2, stock_confirmed: true, vendor_email: 'PRIVATE'}]};
  });
  ok(!JSON.stringify(context).includes('PRIVATE'));
  ok(JSON.stringify(context).includes('stock_qty'));
  ok(typeof context.catalogue_scope === 'string');
});
Deno.test('failed catalogue read never looks like empty successful stock', async () => {
  const context = await assistantContext('available products', async () => { throw Error(); });
  ok(!context.catalogue_sample && context.catalogue_error);
});
Deno.test('unsupported questions make no private reads', async () => {
  await assistantContext('Write my homework', async () => { throw Error('Must not call'); });
});
