@foreach ($categories as $category)
    @if ($category->products->isNotEmpty())
        <section class="mb-6">
            <h3 class="mb-3 text-base font-semibold">{{ $category->name }}</h3>
            <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
                @foreach ($category->products as $product)
                    <article class="menu-item flex items-center gap-3 rounded-2xl border border-espresso/10 bg-white p-3 shadow-sm" data-name="{{ strtolower($product->name) }}">
                        @if ($product->image)
                            <img src="{{ asset('storage/' . $product->image) }}" alt="{{ $product->name }}" class="h-14 w-14 rounded-xl object-cover">
                        @else
                            <div class="flex h-14 w-14 items-center justify-center rounded-xl bg-cream">☕</div>
                        @endif
                        <div class="min-w-0 flex-1">
                            <p class="truncate font-medium">{{ $product->name }}</p>
                            <p class="text-xs text-espresso/60">₱{{ number_format($product->base_price, 2) }}</p>
                        </div>
                        <form method="POST" action="{{ route('staff.menu.toggle', $product) }}">@csrf
                            <button class="rounded-lg px-3 py-2 text-xs font-semibold {{ $product->is_available ? 'bg-success/10 text-success' : 'bg-red-100 text-red-700' }}">
                                {{ $product->is_available ? '● Available' : '○ Sold out' }}
                            </button>
                        </form>
                    </article>
                @endforeach
            </div>
        </section>
    @endif
@endforeach
