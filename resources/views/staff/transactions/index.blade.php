@extends('layouts.staff')
@section('title', 'Transactions')
@section('content')
<div class="mb-5 flex flex-wrap items-end justify-between gap-3 print:hidden">
    <div><h2 class="text-2xl font-semibold">Daily Transactions</h2><p class="mt-1 text-sm text-espresso/60">Sales and payment summary · live updates every 10 seconds</p></div>
    <form id="transaction-filter" method="GET" class="flex flex-wrap items-center gap-2">
        <input type="date" name="date" value="{{ $date }}" class="rounded-lg border border-espresso/20 bg-white px-3 py-2 text-sm">
        <button class="rounded-lg bg-espresso px-4 py-2 text-sm text-cream">Apply date</button>
        <button type="button" onclick="window.print()" class="rounded-lg border border-espresso/20 bg-white px-4 py-2 text-sm">Print</button>
    </form>
</div>
<p class="hidden print:block mb-3 font-semibold">End-of-day Summary · {{ \Carbon\Carbon::parse($date)->format('M d, Y') }}</p>
<div id="transaction-content">@include('staff.transactions._content')</div>
@endsection
@push('scripts')
<script>
const transactionUrl = @json(route('staff.transactions.partial'));
const transactionContent = document.getElementById('transaction-content');
const transactionFilter = document.getElementById('transaction-filter');
async function refreshTransactions() {
  if (document.hidden || transactionFilter.contains(document.activeElement)) return;
  const params = new URLSearchParams(new FormData(transactionFilter));
  try {
    const response = await fetch(`${transactionUrl}?${params}`, { headers: { 'X-Requested-With': 'XMLHttpRequest' } });
    if (response.ok) transactionContent.innerHTML = await response.text();
  } catch (_) { /* Retry on the next poll. */ }
}
transactionFilter.addEventListener('submit', event => { event.preventDefault(); refreshTransactions(); });
setInterval(refreshTransactions, 10000);
</script>
@endpush
