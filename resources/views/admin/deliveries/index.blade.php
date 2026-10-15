@extends('layouts.admin')
@section('title', 'Deliveries')
@section('content')
<div class="mb-6 flex flex-wrap items-end justify-between gap-3">
    <div>
        <h1 class="text-2xl font-semibold">Delivery Monitoring</h1>
        <p class="mt-1 text-sm text-espresso/60">Review rider assignments, estimated distance, and delivery proof photos.</p>
    </div>
    <div class="flex gap-2 text-sm">
        <a href="?filter=active" class="rounded-lg px-4 py-2 {{ $filter === 'active' ? 'bg-espresso text-cream' : 'bg-white' }}">Active</a>
        <a href="?filter=all" class="rounded-lg px-4 py-2 {{ $filter === 'all' ? 'bg-espresso text-cream' : 'bg-white' }}">All deliveries</a>
        <a href="{{ route('admin.gps.index') }}" class="rounded-lg bg-caramel px-4 py-2 text-white">Live Map</a>
    </div>
</div>

<div class="overflow-x-auto rounded-2xl bg-white shadow-sm">
    <table class="w-full min-w-[960px] text-sm">
        <thead class="bg-espresso/5 text-left text-espresso/70">
            <tr>
                <th class="p-3">Order #</th>
                <th class="p-3">Customer</th>
                <th class="p-3">Delivery Address</th>
                <th class="p-3">Rider</th>
                <th class="p-3">Status</th>
                <th class="p-3">Distance</th>
                <th class="p-3">Rider Photo</th>
            </tr>
        </thead>
        <tbody>
            @forelse ($orders as $order)
                <tr class="border-t border-espresso/10 align-middle">
                    <td class="p-3"><a href="{{ route('admin.orders.show', $order) }}" class="font-medium text-caramel hover:underline">{{ $order->order_number }}</a></td>
                    <td class="p-3">{{ $order->user->name ?? 'Guest' }}</td>
                    <td class="max-w-xs truncate p-3" title="{{ $order->delivery_address }}">{{ $order->delivery_address ?: '—' }}</td>
                    <td class="p-3">{{ $order->delivery?->rider?->name ?? 'Not assigned' }}</td>
                    <td class="p-3">@include('admin.partials.badge', ['status' => $order->status])</td>
                    <td class="p-3 whitespace-nowrap">
                        @if ($order->delivery?->distance_km !== null)
                            {{ number_format((float) $order->delivery->distance_km, 2) }} km
                            <span class="block text-xs text-espresso/50">Estimated route</span>
                        @else
                            <span class="text-espresso/50">Unavailable</span>
                        @endif
                    </td>
                    <td class="p-3">
                        @if ($order->delivery?->proof_photo_url)
                            <a href="{{ $order->delivery->proof_photo_url }}" target="_blank" rel="noopener" class="group inline-flex items-center gap-2">
                                <img src="{{ $order->delivery->proof_photo_url }}" alt="Delivery proof for {{ $order->order_number }}" loading="lazy" class="h-14 w-16 rounded-lg border border-espresso/10 object-cover group-hover:opacity-80">
                                <span class="text-xs font-medium text-caramel">View photo</span>
                            </a>
                            @if ($order->delivery->delivered_at)
                                <span class="mt-1 block text-xs text-espresso/50">{{ $order->delivery->delivered_at->format('M j, Y g:i A') }}</span>
                            @endif
                        @else
                            <span class="text-xs text-espresso/50">No photo uploaded</span>
                        @endif
                    </td>
                </tr>
            @empty
                <tr><td colspan="7" class="p-6 text-center text-espresso/50">No deliveries found.</td></tr>
            @endforelse
        </tbody>
    </table>
</div>
<div class="mt-4">{{ $orders->links() }}</div>
@endsection
