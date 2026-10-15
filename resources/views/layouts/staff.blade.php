<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>@yield('title', 'Staff') | KJM Coffee Shop</title>
    <link href="https://fonts.bunny.net/css?family=poppins:400,500,600,700" rel="stylesheet">
    @vite(['resources/css/app.css', 'resources/js/app.js'])
    <style>
        .staff-scrollbar { scrollbar-width: thin; scrollbar-color: #9b694d transparent; }
        .staff-scrollbar::-webkit-scrollbar { width: 6px; height: 6px; }
        .staff-scrollbar::-webkit-scrollbar-thumb { background: #9b694d; border-radius: 8px; }
        @media (max-width: 767px) { .staff-sidebar { display: none; } }
    </style>
</head>
<body class="min-h-screen bg-[#f6f1eb] font-sans text-[#30221c] antialiased">
@php
    $pending = \App\Models\Order::where('status', 'pending')->count();
    $tabs = [
        ['staff.orders', 'Orders', 'staff/orders*', 'clipboard-list'],
        ['staff.pos', 'Walk-in POS', 'staff/pos*', 'shopping-bag'],
        ['staff.menu', 'Menu Availability', 'staff/menu*', 'coffee'],
        ['staff.transactions', 'Transactions', 'staff/transactions*', 'clock'],
    ];
@endphp
<div class="min-h-screen md:flex">
    <aside class="staff-sidebar sticky top-0 flex h-screen w-[224px] shrink-0 flex-col bg-gradient-to-b from-[#27170f] to-[#3d2419] text-[#fff8f1]">
        <a href="{{ route('staff.orders') }}" class="flex h-[86px] shrink-0 items-center gap-3 border-b border-white/10 px-5">
            <span aria-hidden="true" class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full border border-white/20 bg-white text-2xl">☕</span>
            <span class="min-w-0"><strong class="block truncate text-[17px]">KJM Coffee Shop</strong><small class="block text-xs text-white/65">Fresh Coffee · Good Food</small></span>
        </a>
        <div class="px-5 pb-2 pt-6 text-[10px] font-semibold uppercase tracking-[.18em] text-[#d8bba7]">Operations</div>
        <nav class="staff-scrollbar flex-1 space-y-1 overflow-y-auto px-3 pb-4">
            @foreach ($tabs as [$route, $label, $pattern, $icon])
                <a href="{{ route($route) }}" class="flex min-h-11 items-center gap-3 rounded-xl px-3 py-2.5 text-sm transition {{ request()->is($pattern) ? 'bg-[#96603e] font-semibold text-white shadow-sm' : 'text-white/80 hover:bg-white/10 hover:text-white' }}">
                    <span aria-hidden="true" class="w-5 text-center">{{ ['clipboard-list' => '▤', 'shopping-bag' => '▣', 'coffee' => '☕', 'clock' => '◷'][$icon] }}</span>
                    <span class="flex-1">{{ $label }}</span>
                    @if ($route === 'staff.orders')
                        <span id="nav-pending" class="rounded-full bg-[#d78243] px-2 py-0.5 text-[11px] text-white {{ $pending ? '' : 'hidden' }}">{{ $pending }}</span>
                    @endif
                </a>
            @endforeach
        </nav>
    </aside>

    <div class="flex min-h-screen min-w-0 flex-1 flex-col">
        <header class="sticky top-0 z-30 border-b border-[#eadfd5] bg-[#fffaf5]/95 shadow-sm backdrop-blur">
            <div class="flex min-h-[72px] items-center justify-between gap-4 px-4 sm:px-7">
                <div class="min-w-0">
                    <p class="text-[10px] font-semibold uppercase tracking-[.18em] text-[#967966]">Staff workspace</p>
                    <h1 class="truncate text-lg font-semibold text-[#352219]">@yield('title', 'Staff')</h1>
                </div>
                <div class="flex shrink-0 items-center gap-3">
                    <span class="hidden text-right sm:block"><strong class="block text-sm">{{ auth()->user()->name }}</strong><small class="text-xs text-[#8c7666]">{{ ucfirst(auth()->user()->role) }}</small></span>
                    <span class="flex h-10 w-10 items-center justify-center rounded-full bg-[#f1dfcf] font-semibold text-[#603b27]">{{ mb_substr(auth()->user()->name, 0, 1) }}</span>
                    @if (auth()->user()->role === 'admin')
                        <a href="{{ route('admin.dashboard') }}" class="rounded-lg border border-[#e6d7c9] px-3 py-2 text-xs font-medium hover:bg-[#f8eee5]">Admin</a>
                    @endif
                    <form method="POST" action="{{ route('logout') }}">@csrf
                        <button class="rounded-lg px-3 py-2 text-sm text-[#79533e] hover:bg-[#f5e9df]">Log out</button>
                    </form>
                </div>
            </div>
            <nav class="staff-scrollbar flex gap-1 overflow-x-auto border-t border-[#eee4db] px-3 py-2 md:hidden">
                @foreach ($tabs as [$route, $label, $pattern, $icon])
                    <a href="{{ route($route) }}" class="shrink-0 rounded-lg px-3 py-2 text-xs {{ request()->is($pattern) ? 'bg-[#603b27] text-white' : 'text-[#624c3e] hover:bg-[#f0e5da]' }}">{{ $label }}</a>
                @endforeach
            </nav>
        </header>

        <main class="w-full flex-1 p-4 sm:p-6 lg:p-7">
            @if (session('success'))
                <div class="mb-4 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">{{ session('success') }}</div>
            @endif
            @if (session('error'))
                <div class="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{{ session('error') }}</div>
            @endif
            @yield('content')
        </main>
    </div>
</div>
@stack('scripts')
</body>
</html>
