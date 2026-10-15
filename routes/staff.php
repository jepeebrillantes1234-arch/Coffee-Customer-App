<?php

use App\Http\Controllers\Staff\OrderController;
use App\Http\Controllers\Staff\PosController;
use App\Http\Controllers\Staff\ProductController;
use App\Http\Controllers\Staff\TransactionController;
use Illuminate\Support\Facades\Route;

Route::middleware(['auth','role:staff,admin'])->prefix('staff')->name('staff.')->group(function(){
    Route::get('/',fn()=>redirect()->route('staff.orders'))->name('home');
    Route::get('/orders',[OrderController::class,'index'])->name('orders');
    Route::get('/orders/partial',[OrderController::class,'partial'])->name('orders.partial');
    Route::post('/orders/{order}/advance',[OrderController::class,'advance'])->name('orders.advance');
    Route::post('/orders/{order}/assign-available',[OrderController::class,'assignAvailable'])->name('orders.assign-available');
    Route::post('/deliveries/{delivery}/remit',[OrderController::class,'remit'])->name('deliveries.remit');
    Route::get('/pos',[PosController::class,'index'])->name('pos');
    Route::get('/pos/catalog',[PosController::class,'catalog'])->name('pos.catalog');
    Route::post('/pos',[PosController::class,'store'])->name('pos.store');
    Route::get('/pos/{order}/receipt',[PosController::class,'receipt'])->name('pos.receipt');
    Route::get('/menu',[ProductController::class,'index'])->name('menu');
    Route::get('/menu/partial',[ProductController::class,'partial'])->name('menu.partial');
    Route::post('/menu/{product}/toggle',[ProductController::class,'toggle'])->name('menu.toggle');
    Route::get('/transactions',[TransactionController::class,'index'])->name('transactions');
    Route::get('/transactions/partial',[TransactionController::class,'partial'])->name('transactions.partial');
});
