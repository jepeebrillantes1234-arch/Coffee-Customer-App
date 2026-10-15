@php $typeLabel = ['delivery' => 'Delivery', 'pickup' => 'Pickup', 'walkin' => 'Walk-in']; @endphp
<div class="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
    @foreach ([
        ['Total Sales', '₱' . number_format($summary['sales'], 2), $summary['count'] . ' completed orders'],
        ['Counter Cash', '₱' . number_format($summary['counter_cash'], 2), 'Paid walk-in and pickup orders'],
        ['Cash on Delivery', '₱' . number_format($summary['cod'], 2), 'Collected delivery payments'],
        ['Discounts', '₱' . number_format($summary['discounts'], 2), $summary['cancelled'] . ' canceled/rejected · ' . $summary['active'] . ' active'],
    ] as [$label, $value, $subtext])
        <article class="rounded-2xl border border-espresso/10 bg-white p-4 shadow-sm sm:p-5"><p class="text-xs text-espresso/60">{{ $label }}</p><p class="mt-1 text-xl font-semibold">{{ $value }}</p><p class="mt-1 text-xs text-espresso/50">{{ $subtext }}</p></article>
    @endforeach
</div>
<div class="mb-6 grid gap-4 md:grid-cols-2">
    <section class="rounded-2xl border border-espresso/10 bg-white p-5 shadow-sm">
        <h3 class="mb-2 font-semibold">Sales by Order Type</h3>
        @forelse ($byType as $type => $data)
            <div class="flex justify-between border-t border-espresso/5 py-2 text-sm"><span>{{ $typeLabel[$type] ?? $type }} ({{ $data['n'] }})</span><span>₱{{ number_format($data['sum'], 2) }}</span></div>
        @empty <p class="text-sm text-espresso/50">No completed sales yet.</p> @endforelse
    </section>
    <section class="rounded-2xl border border-espresso/10 bg-white p-5 shadow-sm">
        <h3 class="mb-2 font-semibold">Walk-in Sales by Cashier</h3>
        @forelse ($byCashier as $name => $data)
            <div class="flex justify-between border-t border-espresso/5 py-2 text-sm"><span>{{ $name }} ({{ $data['n'] }})</span><span>₱{{ number_format($data['sum'], 2) }}</span></div>
        @empty <p class="text-sm text-espresso/50">No walk-in sales yet.</p> @endforelse
    </section>
</div>
<div class="overflow-x-auto rounded-2xl border border-espresso/10 bg-white shadow-sm">
    <table class="w-full text-left text-sm">
        <thead class="bg-espresso/5 text-espresso/70"><tr><th class="p-3">Time</th><th class="p-3">Order #</th><th class="p-3">Type</th><th class="p-3">Customer</th><th class="p-3">Status</th><th class="p-3">Payment</th><th class="p-3 text-right">Total</th></tr></thead>
        <tbody>
            @forelse ($orders as $order)
                <tr class="border-t border-espresso/10">
                    <td class="whitespace-nowrap p-3">{{ $order->created_at->format('h:i A') }}</td>
                    <td class="p-3 font-medium">{{ $order->order_number }}</td>
                    <td class="p-3">{{ $typeLabel[$order->order_type] ?? $order->order_type }}</td>
                    <td class="p-3">{{ $order->user->name ?? 'Walk-in' }}</td>
                    <td class="p-3">@include('admin.partials.badge', ['status' => $order->status])</td>
                    <td class="p-3">{{ strtoupper($order->payment_method) }} · @include('admin.partials.badge', ['status' => $order->payment_status])</td>
                    <td class="p-3 text-right">₱{{ number_format($order->total, 2) }}</td>
                </tr>
            @empty
                <tr><td colspan="7" class="p-6 text-center text-espresso/50">No transactions for this date.</td></tr>
            @endforelse
        </tbody>
    </table>
</div>
