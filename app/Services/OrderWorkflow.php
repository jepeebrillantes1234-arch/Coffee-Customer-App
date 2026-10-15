<?php
namespace App\Services;

use App\Models\Delivery;
use App\Models\Order;
use App\Models\Payment;
use App\Models\User;
use App\Support\Geo;
use App\Support\Notifier;
use App\Support\Settings;
use Illuminate\Support\Facades\DB;

class OrderWorkflow
{
    public function confirm(Order $o) { return $this->change($o,'pending','confirmed'); }
    public function preparing(Order $o) { return $this->change($o,'confirmed','preparing'); }
    public function ready(Order $o)
    {
        $this->change($o, 'preparing', 'ready');
        return $this->assignAvailableRider($o);
    }

    public function assignAvailableRider(Order $o)
    {
        if ($o->order_type !== 'delivery' || $o->status !== 'ready') {
            throw new \DomainException('READY na delivery order lang ang maaaring i-assign.');
        }

        $rider = User::query()
            ->where('role', 'rider')
            ->where('status', 'active')
            ->whereHas('riderProfile', fn ($query) => $query
                ->where('is_approved', true)
                ->where('is_available', true))
            ->whereDoesntHave('deliveries', fn ($query) => $query
                ->whereIn('status', ['assigned', 'accepted', 'picked_up', 'on_the_way']))
            ->orderBy('id')
            ->first();

        if (! $rider) {
            return 'Naka-READY ang order, pero walang available na rider. I-online ang rider app at subukan ulit ang assignment.';
        }

        $this->assignRider($o, (int) $rider->id);
        return null;
    }
    public function complete(Order $o)
    {
        if (!in_array($o->status,['delivered','ready'],true) || ($o->order_type==='delivery' && $o->status!=='delivered')) throw new \DomainException('Hindi pa maaaring tapusin ang order.');
        if ($o->order_type==='delivery' && $o->payment_method==='cod') {
            $o->loadMissing('delivery');
            if (!$o->delivery?->cash_remitted_at) throw new \DomainException('Kumpirmahin muna ng staff ang cash na ini-remit ng rider.');
        }
        if ($o->order_type==='pickup' && $o->payment_method==='cash' && $o->payment_status!=='paid') {
            $o->update(['payment_status'=>'paid']);
            Payment::updateOrCreate(['order_id'=>$o->id],['method'=>'cash','amount'=>$o->total,'status'=>'paid','paid_at'=>now()]);
        }
        return $this->set($o,'completed');
    }
    public function reject(Order $o,string $reason)
    {
        if (!in_array($o->status,['pending','confirmed'],true)) throw new \DomainException('Hindi na maaaring tanggihan ang order.');
        $o->reject_reason=$reason; return $this->set($o,'rejected');
    }
    public function cancel(Order $o,string $reason)
    {
        if (!$o->canCancel()) throw new \DomainException('Hindi na maaaring kanselahin ang order.');
        $o->reject_reason=$reason; return $this->set($o,'cancelled');
    }
    public function assignRider(Order $o,int $riderId)
    {
        if ($o->order_type!=='delivery' || $o->status!=='ready') throw new \DomainException('Ready na delivery order lang ang maaaring i-assign.');
        $rider=\App\Models\User::where('role','rider')->where('status','active')->whereHas('riderProfile',fn($q)=>$q->where('is_approved',true))->findOrFail($riderId);
        DB::transaction(function () use ($o, $rider) {
            $delivery = Delivery::firstOrNew(['order_id' => $o->id]);
            $delivery->rider_id = $rider->id;
            $delivery->status = 'assigned';
            $delivery->assigned_at = now();
            if ($delivery->distance_km === null) {
                $delivery->distance_km = $this->estimatedDistance($o);
            }
            $delivery->save();
            $this->set($o, 'rider_assigned');
        });
        return null;
    }

    private function estimatedDistance(Order $order): ?float
    {
        $shopLat = Settings::get('shop_lat');
        $shopLng = Settings::get('shop_lng');
        if (!is_numeric($shopLat) || !is_numeric($shopLng)
            || !is_numeric($order->delivery_lat) || !is_numeric($order->delivery_lng)) {
            return null;
        }

        return Geo::km((float) $shopLat, (float) $shopLng, (float) $order->delivery_lat, (float) $order->delivery_lng);
    }
    private function change(Order $o,string $from,string $to)
    {
        if($o->status!==$from) throw new \DomainException('Hindi tugma ang kasalukuyang status ng order.');
        return $this->set($o,$to);
    }
    private function set(Order $o,string $status)
    {
        $o->status=$status; $o->save();
        DB::table('order_status_logs')->insert(['order_id'=>$o->id,'status'=>$status,'changed_by'=>auth()->id(),'created_at'=>now()]);
        Notifier::order($o,$status); return null;
    }
}


