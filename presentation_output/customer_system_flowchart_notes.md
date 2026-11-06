# KJM Coffee Shop Customer System Flowcharts

These diagrams are based on the inspected Flutter customer app and Laravel API as of November 5, 2026. They describe customer-facing routes and the backend validation that governs them. They do not infer payment success from the presence of a QR image, navigation, or a local Flutter state.

## Diagram files

- `customer_system_flowchart.mmd` - complete main journey from opening the mobile application through authentication, Home, product discovery, cart, checkout, order history/tracking, membership, support, profile, and logout.
- `customer_checkout_payment_flow.mmd` - fulfillment/address selection, server quote, eligible payment methods, order/payment creation, PayMongo QRPh, confirmation, retry, and unpaid expiry.
- `customer_tracking_cancellation_flow.mmd` - My Orders, payment recovery, separate Pickup/Delivery status views, rider map conditions, cancellation reason and backend lock checks.
- `customer_membership_rewards_flow.mmd` - membership purchase and activation, points earning, reward redemption code/history, and separate physical card delivery.
- `customer_service_flowchart.mmd` - authenticated and guest support, rule-based assistant, handoff/contact choice, conversation history, and return to profile/logout.

## PowerPoint slide order

1. Title slide.
2-3. Main Customer System Flowchart (split across two readable slides).
4. Checkout and Payment.
5. Order Tracking and Cancellation.
6. Membership and Rewards.
7. Customer Service.

The Mermaid files are the editable diagram sources. The PowerPoint cover text is editable. The flowchart pages are high-resolution images to preserve their readable layout and can be revised from the accompanying Mermaid sources.

## Verified implementation facts

- App startup initializes Firebase, restores the API/session and theme, shows Splash, then routes a signed-in customer to the customer shell or a signed-out user to Get Started. Login supports email, username, or phone plus password, and Google sign-in. Registration collects name, username, email, phone, password, and confirmation.
- Home loads products, categories, home banners and app configuration. Product discovery includes category browsing, search, promo destinations, discount tags, and best-seller tags where product data marks them. Product details expose supported options and favorites. Cart supports quantity changes, removal, and editing.
- Checkout supports Delivery and Pickup. Delivery requires a selected saved address and coordinates for fee calculation. Laravel generates authoritative totals. Delivery permits COD when enabled; Pickup offers Cash at Pickup or QRPh. QRPh is available only when the app/backend configuration allows it.
- New QRPh Payment Intent details appear in the in-app payment screen. Flutter checks Laravel status; only a server-confirmed paid status produces success. Legacy Checkout Sessions may still open the provider checkout URL when no QR image is present.
- The scheduled `orders:expire-unpaid` task runs every minute. For stale unpaid QRPh product orders (configured default timeout 30 minutes), it checks PayMongo before marking unpaid orders cancelled/expired and archiving them from the active customer list. It retains order/payment records; if PayMongo cannot be checked, expiry is deferred.
- My Orders can reopen payment for an eligible unpaid QRPh order. Customer cancellation requires a reason and backend revalidation under a row lock. The normal customer cancellation endpoint rejects paid or progressed orders; customer support is the escalation route. Cancellation does not claim a refund.
- Delivery tracking displays delivery statuses, rider data/map when assigned, and live location only when available/fresh. Pickup has no rider tracking and shows the shop location. Both use the common order status field/log: for Pickup `ready` is displayed as “Ready for pickup” and `completed` is the terminal completed state. No separate persisted “Already Picked Up” status/timestamp sequence was found.
- Membership is activated only after server-verified payment. Points are awarded for eligible paid orders in delivered/completed states for active members, calculated from item quantity and recorded idempotently. Redeeming a reward deducts points/stock and creates a redemption code; the app displays that code as a QR and retains redemption history.
- Physical membership card delivery requires an active, paid membership, a saved destination, and a separate card-delivery record. It is independent of product-order delivery.
- Customer service is available to signed-in users and guests. The existing assistant uses local rule/keyword matching; messages are persisted, and the system can create an Admin handoff notification. It does not guarantee an immediate human reply.

## Details not confirmed or deliberately not represented as features

- A distinct persisted Pickup status named “Already Picked Up” was not found; diagrams use actual shared `ready` and `completed` states and identify the customer-facing ready label.
- Customer cancellation of paid QRPh orders is not available through the standard customer cancel endpoint. The diagram shows support escalation, not automatic refund.
- No promise of live rider tracking is made when an order has no active rider or location is stale/missing.
- Staff/admin decisions outside the customer app (order preparation, rider assignment, reward handoff, and manual payment review) are represented only as backend/operational transitions where needed to explain the customer's resulting state.

## Source files used

### Flutter customer app

- `lib/main.dart`, `lib/screens/splash_screen.dart`, `lib/screens/get_started_screen.dart`
- `lib/screens/auth_screen.dart`, `lib/screens/register_screen.dart`, `lib/screens/forgot_password_screen.dart`
- `lib/screens/root_screen.dart`, `lib/screens/home_screen.dart`, `lib/screens/menu_screen.dart`, `lib/screens/product_screen.dart`
- `lib/state/cart.dart`, `lib/screens/cart_screen.dart`, `lib/screens/checkout_screen.dart`, `lib/screens/addresses_screen.dart`
- `lib/screens/qrph_payment_screen.dart`, `lib/screens/orders_screen.dart`, `lib/screens/trackorder_screen.dart`, `lib/screens/order_detail_screen.dart`
- `lib/screens/membership_screen.dart`, `lib/screens/redeem_points_screen.dart`
- `lib/screens/support_chat_screen.dart`, `lib/screens/customer_service_sheet.dart`, `lib/screens/profile_screen.dart`

### Laravel backend

- `routes/api.php`, `routes/console.php`
- `app/Http/Controllers/Api/AuthController.php`, `MenuController.php`, `HomeController.php`, `OrderController.php`, `LoyaltyController.php`, `SupportChatController.php`, `MembershipCardDeliveryController.php`
- `app/Services/OrderWorkflow.php`, `PaymentGateway.php`, `LoyaltyService.php`, `SupportAssistant.php`
- `app/Models/Order.php`, `Payment.php`, `Membership.php`, `MembershipPayment.php`, `Delivery.php`, `MembershipCardDelivery.php`, `RewardRedemption.php`, `LoyaltyTransaction.php`, `OrderStatusLog.php`
