<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Receipt {{ $order->order_number }}</title>
    <style>
        * { box-sizing: border-box; }
        body { font-family: 'Courier New', monospace; font-size: 13px; width: 300px; margin: 0 auto; padding: 12px; color: #000; }
        h1 { font-size: 18px; text-align: center; margin: 0; }
        .c { text-align: center; } .r { text-align: right; }
        hr { border: 0; border-top: 1px dashed #000; margin: 8px 0; }
        table { width: 100%; border-collapse: collapse; }
        td { vertical-align: top; padding: 2px 0; }
        .sub { font-size: 11px; color: #444; padding-left: 8px; }
        .tot td { font-weight: bold; font-size: 15px; }
        .no-print { text-align: center; margin-top: 14px; }
        button { padding: 8px 16px; font-size: 14px; }
        @media print { .no-print { display: none; } body { width: auto; } }
    </style>
</head>
<body onload="window.print()">
    <h1>KJM COFFEE SHOP</h1>
    <p class="c">Payment Receipt</p>
    <hr>
    <div>Order #: {{ $order->order_number }}</div>
    <div>Date: {{ $order->created_at->format('M d, Y h:i A') }}</div>
    <div>Cashier: {{ $order->staff->name ?? '—' }}</div>
    @if ($order->notes) <div>{{ $order->notes }}</div> @endif
    <hr>
    <table>
        @foreach ($order->items as $item)
            <tr><td>{{ $item->quantity }} × {{ $item->product_name }}</td><td class="r">{{ number_format($item->total_price, 2) }}</td></tr>
            @if ($item->options->isNotEmpty()) <tr><td colspan="2" class="sub">{{ $item->options->pluck('option_name')->join(', ') }}</td></tr> @endif
            @if ($item->notes) <tr><td colspan="2" class="sub">* {{ $item->notes }}</td></tr> @endif
        @endforeach
    </table>
    <hr>
    <table>
        <tr><td>Subtotal</td><td class="r">{{ number_format($order->subtotal, 2) }}</td></tr>
        @if ($order->discount > 0) <tr><td>Discount</td><td class="r">-{{ number_format($order->discount, 2) }}</td></tr> @endif
        <tr class="tot"><td>TOTAL</td><td class="r">₱{{ number_format($order->total, 2) }}</td></tr>
        @if ($cash !== null)
            <tr><td>Cash</td><td class="r">{{ number_format($cash, 2) }}</td></tr>
            <tr><td>Change</td><td class="r">{{ number_format($change, 2) }}</td></tr>
        @endif
    </table>
    <hr>
    <p class="c">Thank you. Please visit us again.</p>
    <div class="no-print"><button onclick="window.print()">Print</button> <button onclick="window.close()">Close</button></div>
</body>
</html>
