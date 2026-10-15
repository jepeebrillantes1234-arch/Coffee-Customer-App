<div class="grid gap-3">
    @forelse ($orders as $order)
        <article class="rounded-2xl border border-espresso/10 bg-white p-4 shadow-sm">
            <div class="flex flex-wrap justify-between gap-3">
                <div class="min-w-[220px] flex-1">
                    <h2 class="font-semibold">{{ $order->order_number }} · {{ ucfirst(str_replace('_', ' ', $order->status)) }}</h2>
                    <p class="text-sm text-espresso/70">{{ $order->user->name ?? 'Walk-in' }} · {{ ucfirst($order->order_type) }} · ₱{{ number_format($order->total, 2) }}</p>
                    <p class="mt-1 text-sm">{{ $order->items->map(fn ($item) => $item->quantity . ' × ' . $item->product_name)->join(', ') }}</p>
                </div>
                <div class="flex flex-wrap items-center gap-2">
                    @if ($order->status === 'ready' && $order->order_type === 'delivery' && !$order->delivery?->rider_id)
                        <form method="POST" action="{{ route('staff.orders.assign-available', $order) }}">@csrf<button class="rounded-lg bg-caramel px-3 py-2 text-sm text-white">Assign online rider</button></form>
                    @endif
                    @if ($order->delivery?->rider)
                        <p class="text-sm text-success">Rider: {{ $order->delivery->rider->name }} · {{ ucfirst(str_replace('_', ' ', $order->delivery->status)) }}</p>
                    @endif
                    @if ($order->status === 'pending')
                        <form method="POST" action="{{ route('staff.orders.advance', $order) }}">@csrf<input type="hidden" name="action" value="confirm"><button class="rounded-lg bg-espresso px-3 py-2 text-sm text-white">Confirm</button></form>
                    @elseif ($order->status === 'confirmed')
                        <form method="POST" action="{{ route('staff.orders.advance', $order) }}">@csrf<input type="hidden" name="action" value="preparing"><button class="rounded-lg bg-espresso px-3 py-2 text-sm text-white">Start preparing</button></form>
                    @elseif ($order->status === 'preparing')
                        <form method="POST" action="{{ route('staff.orders.advance', $order) }}">@csrf<input type="hidden" name="action" value="ready"><button class="rounded-lg bg-espresso px-3 py-2 text-sm text-white">Mark ready</button></form>
                    @elseif ($order->status === 'ready' && $order->order_type !== 'delivery')
                        <form method="POST" action="{{ route('staff.orders.advance', $order) }}">@csrf<input type="hidden" name="action" value="complete"><button class="rounded-lg bg-success px-3 py-2 text-sm text-white">Complete order</button></form>
                    @elseif ($order->status === 'delivered' && $order->delivery)
                        <form method="POST" action="{{ route('staff.deliveries.remit', $order->delivery) }}">@csrf<button class="rounded-lg bg-success px-3 py-2 text-sm text-white">Confirm cash received / complete</button></form>
                    @endif
                </div>
            </div>
        </article>
    @empty
        <p class="rounded-2xl bg-white p-6 text-espresso/60">There are no active orders.</p>
    @endforelse
</div>
