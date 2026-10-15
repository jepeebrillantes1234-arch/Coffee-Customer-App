@extends('layouts.staff')
@section('title', 'Menu Availability')
@section('content')
<div class="mb-5 flex flex-wrap items-center justify-between gap-3">
    <div><h2 class="text-2xl font-semibold">Menu Availability</h2><p class="mt-1 text-sm text-espresso/60">Changes sync to the customer app and POS automatically.</p></div>
    <div class="flex items-center gap-2 text-xs text-espresso/60"><span class="h-2 w-2 rounded-full bg-success"></span><span id="live-state">Live updates on</span></div>
</div>
<div class="mb-4"><input id="q" placeholder="Search menu items..." class="w-full max-w-sm rounded-xl border border-espresso/20 bg-white px-4 py-2.5 text-sm"></div>
<div id="menu-items">@include('staff.menu._items')</div>
@endsection

@push('scripts')
<script>
const MENU_PARTIAL_URL = @json(route('staff.menu.partial'));
const menuItems = document.getElementById('menu-items');
const searchBox = document.getElementById('q');
function filterMenu() {
  const query = searchBox.value.trim().toLowerCase();
  menuItems.querySelectorAll('.menu-item').forEach(item => item.classList.toggle('hidden', query && !item.dataset.name.includes(query)));
}
searchBox.addEventListener('input', filterMenu);
menuItems.addEventListener('submit', async event => {
  const form = event.target.closest('form');
  if (!form) return;
  event.preventDefault();
  try {
    const response = await fetch(form.action, {
      method: 'POST',
      body: new FormData(form),
      headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
    });
    if (!response.ok) throw new Error('Could not update item availability.');
    await refreshMenu();
  } catch (error) {
    document.getElementById('live-state').textContent = error.message;
  }
});
async function refreshMenu() {
  if (document.hidden) return;
  try {
    const response = await fetch(MENU_PARTIAL_URL, { headers: { 'X-Requested-With': 'XMLHttpRequest' } });
    if (!response.ok) return;
    menuItems.innerHTML = await response.text();
    filterMenu();
  } catch (_) { /* Retry on the next poll. */ }
}
setInterval(refreshMenu, 8000);
</script>
@endpush
