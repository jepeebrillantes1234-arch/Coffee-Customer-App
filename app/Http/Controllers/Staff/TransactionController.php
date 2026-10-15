<?php
namespace App\Http\Controllers\Staff;

use App\Http\Controllers\Controller;
use App\Models\Order;
use Illuminate\Http\Request;

class TransactionController extends Controller
{
    public function index(Request $request)
    {
        return view('staff.transactions.index', $this->reportData($request));
    }

    public function partial(Request $request)
    {
        return response()->view('staff.transactions._content', $this->reportData($request));
    }

    private function reportData(Request $request): array
    {
        $date = $request->input('date', now()->toDateString());
        $orders = Order::with(['user:id,name', 'staff:id,name'])
            ->whereDate('created_at', $date)->orderByDesc('id')->get();
        $done = $orders->whereIn('status', ['delivered', 'completed']);
        $summary = [
            'sales' => $done->sum('total'),
            'count' => $done->count(),
            'discounts' => $done->sum('discount'),
            'active' => $orders->whereNotIn('status', ['completed', 'delivered', 'cancelled', 'rejected'])->count(),
            'cancelled' => $orders->whereIn('status', ['cancelled', 'rejected'])->count(),
            'counter_cash' => $done->whereIn('order_type', ['walkin', 'pickup'])->where('payment_status', 'paid')->where('payment_method', 'cash')->sum('total'),
            'cod' => $done->where('order_type', 'delivery')->where('payment_status', 'paid')->sum('total'),
        ];
        $byType = $done->groupBy('order_type')->map(fn ($group) => ['n' => $group->count(), 'sum' => $group->sum('total')]);
        $byCashier = $done->where('order_type', 'walkin')->groupBy(fn ($order) => optional($order->staff)->name ?? '—')
            ->map(fn ($group) => ['n' => $group->count(), 'sum' => $group->sum('total')]);

        return compact('date', 'orders', 'summary', 'byType', 'byCashier');
    }
}
