<?php
namespace App\Http\Controllers\Staff;

use App\Http\Controllers\Controller;
use App\Models\Delivery;
use App\Models\Order;
use App\Services\OrderWorkflow;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class OrderController extends Controller
{
    public function index() { $orders=$this->orders(); $pendingCount=Order::where('status','pending')->count(); return view('staff.orders.index',compact('orders','pendingCount')); }
    public function partial() { $orders=$this->orders(); return response()->view('staff.orders._list',compact('orders'))->header('X-Pending',Order::where('status','pending')->count()); }
    public function advance(Order $order, Request $request, OrderWorkflow $workflow)
    {
        try {
            $notice = match ($request->input('action')) {
                'confirm' => $workflow->confirm($order),
                'preparing' => $workflow->preparing($order),
                'ready' => $workflow->ready($order),
                'assign_available' => $workflow->assignAvailableRider($order),
                'complete' => $workflow->complete($order),
                default => throw new \DomainException('Unknown order action.'),
            };
        } catch (\DomainException $e) {
            if ($request->expectsJson()) return response()->json(['message' => $e->getMessage()], 422);
            return back()->with('error', $e->getMessage());
        }

        if (is_string($notice) && $notice !== '') {
            if ($request->expectsJson()) return response()->json(['message' => $notice], 422);
            return back()->with('error', $notice);
        }

        if ($request->expectsJson()) return response()->json(['success' => true, 'message' => 'Order updated.']);
        return back()->with('success', 'Order updated.');
    }

    public function assignAvailable(Order $order, OrderWorkflow $workflow)
    {
        try {
            $notice = $workflow->assignAvailableRider($order);
        } catch (\DomainException $e) {
            if (request()->expectsJson()) return response()->json(['message' => $e->getMessage()], 422);
            return back()->with('error', $e->getMessage());
        }

        if (is_string($notice) && $notice !== '') {
            if (request()->expectsJson()) return response()->json(['message' => $notice], 422);
            return back()->with('error', $notice);
        }

        if (request()->expectsJson()) return response()->json(['success' => true, 'message' => 'Delivery assigned to an online rider.']);
        return back()->with('success', 'Delivery assigned to an online rider.');
    }

    public function remit(Request $request,Delivery $delivery)
    {
        $order=$delivery->order;
        if(!$order || $order->status!=='delivered') {
            if ($request->expectsJson()) return response()->json(['message' => 'Only delivered orders can be remitted.'], 422);
            return back()->with('error','Only delivered orders can be remitted.');
        }
        if($order->payment_method==='cod' && !$delivery->cash_collected_at) {
            if ($request->expectsJson()) return response()->json(['message' => 'No COD cash has been recorded by the rider yet.'], 422);
            return back()->with('error','No COD cash has been recorded by the rider yet.');
        }
        DB::transaction(function()use($request,$delivery,$order){
            if($order->payment_method==='cod' && !$delivery->cash_remitted_at) $delivery->update(['cash_remitted_at'=>now(),'cash_remitted_by'=>$request->user()->id]);
            $order->update(['status'=>'completed']);
            DB::table('order_status_logs')->insert(['order_id'=>$order->id,'status'=>'completed','changed_by'=>$request->user()->id,'created_at'=>now()]);
            \App\Support\Notifier::order($order->fresh(),'completed');
        });
        if ($request->expectsJson()) return response()->json(['success' => true, 'message' => 'Cash handover recorded and order completed.']);
        return back()->with('success','Cash handover recorded and order completed.');
    }
    private function orders() { return Order::with(['user:id,name','items','delivery.rider:id,name'])->whereIn('status',['pending','confirmed','preparing','ready','rider_assigned','picked_up','on_the_way','delivered'])->latest('id')->limit(100)->get(); }
}
