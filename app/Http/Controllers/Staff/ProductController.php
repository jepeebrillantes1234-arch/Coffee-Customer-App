<?php
namespace App\Http\Controllers\Staff;

use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\Product;
use App\Support\Activity;

class ProductController extends Controller
{
    public function index()
    {
        $categories = Category::with(['products' => fn ($q) => $q->orderBy('name')])->orderBy('sort_order')->get();
        return view('staff.menu.index', compact('categories'));
    }

    public function partial()
    {
        $categories = Category::with(['products' => fn ($q) => $q->orderBy('name')])->orderBy('sort_order')->get();
        return response()->view('staff.menu._items', compact('categories'));
    }

    // I-toggle ang Available <-> Sold out
    public function toggle(Product $product)
    {
        $product->update(['is_available' => !$product->is_available]);
        Activity::log('availability', 'products', "{$product->name}: " . ($product->is_available ? 'available' : 'sold out'));

        $message = "{$product->name} is " . ($product->is_available ? 'available again.' : 'sold out.');
        if (request()->expectsJson()) {
            return response()->json(['success' => true, 'message' => $message]);
        }
        return back()->with('success', $message);
    }
}
