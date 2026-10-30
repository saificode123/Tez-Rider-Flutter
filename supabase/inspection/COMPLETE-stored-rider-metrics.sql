begin read only;
select jsonb_build_object(
 'project','igeisilhtmglgnqvllrx','order_id',3180,
 'metrics_rows',(select count(*)from final2_private.rider_delivery_metrics where order_id=3180 and rider_id=999 and assignment_id=593),
 'duration_stored',exists(select 1 from final2_private.rider_delivery_metrics where order_id=3180 and rider_id=999 and duration_seconds>=0),
 'completed_deliveries',(select completed_deliveries from final2_private.rider_performance where rider_id=999),
 'timed_deliveries',(select timed_deliveries from final2_private.rider_performance where rider_id=999),
 'completion_rate',(select completion_rate from final2_private.rider_performance where rider_id=999),
 'earned_amount',(select sum(amount)from final_delivery_private.rider_earnings where order_id=3180 and rider_id=999)
)as metrics;
rollback;
