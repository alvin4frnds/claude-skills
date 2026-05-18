# Clean-Code Principles — Full Catalog

This is the deep-dive reference for the `clean-code` skill: **63 principles** distilled from ~85 Laracasts videos (Jeffrey Way, Adam Wathan, Aaron Francis, Jason McCreary, Katerina Trajchevska, et al.) covering *10 Techniques for Cleaner Code*, *Simple Rules for Simpler Code*, *Code Reflections*, *Long-form Refactoring Workshops*, *SOLID Principles in PHP*, *BaseCode Reloaded* (2025), *Write Code That's Easy to Maintain*, *Whip Monstrous Code Into Shape*, *Object-Oriented Principles in PHP (2024 Edition)*, and *How to Read Code*.

SKILL.md gives the operational summary; consult this catalog when a specific principle needs full motivation, edge cases, or a canonical code example. Examples are PHP unless noted; the rules transfer to any language.

## Categories

- **Naming** — class, method, variable, and constant names; how the words you pick reveal or hide intent.
- **Control flow** — conditionals, branching, indentation depth, early returns, the shape of a method body.
- **Functions and methods** — extraction, inlining, parameter design, return shape, single-responsibility at the method level.
- **Encapsulation and data design** — where state and behavior live; objects vs. primitives; tell-don't-ask; pushing decisions onto the right owner.
- **Abstraction and polymorphism** — interfaces, dependency direction, strategy/factory/template patterns, ISP/OCP/LSP/DIP, modern PHP syntactic sugar that reduces boilerplate.
- **Architecture and module shape** — controllers, use cases, services, repositories, file/directory layout, co-location, named extraction patterns for fat classes.
- **Reading code** — how to understand an unfamiliar codebase before changing it; bootstrap-first, route-first, trace-to-origin, verify-with-dd, re-implement-with-TDD.
- **Refactoring practice** — the discipline: micro-steps, evaluation, reversion, "is it better?", named techniques (proximity rule, three-step blocks, rule of three, scratch refactor, sprout/wrap, symmetry).
- **Testing** — what tests buy you, mocking, control cases, behavior-vs-implementation, endpoint-driven testing, characterization tests + seams for legacy code.

## Principles

### Replace magic numbers with named constants
- **Category:** Naming
- **One-line rule:** Replace any numeric literal whose meaning isn't self-evident with a named constant on the class that owns the concept.
- **Why it matters:** Bare literals carry zero intent — even ones you wrote and remember today will be opaque to a teammate or to you in six months. Familiarity is not documentation; HTTP status codes like `403` are still magic numbers. The constant's name tells the reader what the value *means*, not just what it *is*.
- **How to apply:**
  - Define `SCREAMING_SNAKE_CASE` constants on the model that owns the concept (point amounts on `Experience`, not on `User`).
  - Name the constant after the *action or meaning* that produces the value (`UPGRADE_ACCOUNT`, `COMPLETE_LESSON`), not the value (`TWO_THOUSAND`).
  - Apply this to protocol numbers too — prefer `Response::HTTP_FORBIDDEN` over `403`.
  - Refactor only inputs/arguments that represent domain actions; leave aggregate-value assertions in tests as literals so the test asserts a concrete expected total.
  - Replace one literal at a time and re-run the test suite between swaps.
- **Canonical code example (PHP):**
```php
// Before
$user->earnExperience(2000);
$user->earnExperience(100);

// After
$user->earnExperience(Experience::UPGRADE_ACCOUNT);
$user->earnExperience(Experience::COMPLETE_LESSON);
```
- **Sources:** An Alternative to Magic Numbers [00:33–03:55].

### Don't abbreviate names
- **Category:** Naming
- **One-line rule:** Spell every class, method, and variable name out in full — never abbreviate to save keystrokes.
- **Why it matters:** Modern editors auto-complete; muscle memory makes the full word as fast to type. There is "literally zero benefit" to `Trans` over `Translator` or `UserRepo` over `UserRepository`, and the abbreviation forces every future reader to decode it. Each tiny infraction is harmless; a thousand of them compound into an unreadable codebase.
- **How to apply:**
  - The only universally accepted abbreviation is `id`.
  - Use `x`/`y` only for actual geometric coordinates — never as loop indices.
  - Name loop variables with the singular form of the collection (`person` for `people`), not a single letter.
  - `i` for an index is fine; `h` for a heading is not.
- **Canonical code example (PHP):**
```php
// Before
foreach ($people as $x) { /* ... */ }
class UserRepo { /* ... */ }

// After
foreach ($people as $person) { /* ... */ }
class UserRepository { /* ... */ }
```
- **Sources:** No Abbreviations [00:45–03:04]; Beware the Flying V Complication [15:43] (`h` → `heading`).

### Name methods and classes for the domain meaning, not the implementation
- **Category:** Naming
- **One-line rule:** Choose names that describe what something *means* in the domain, not how it currently works or when it currently runs.
- **Why it matters:** A name like `scopeRecent($date)` reads as "last N days" but if the implementation matches one exact day, every reader will be misled. Names that describe behavior survive refactors; names that describe a current implementation become lies the moment the implementation changes.
- **How to apply:**
  - Rename when the implementation drifts from the name (`scopeRecent` → `scopeSubscribedOn`).
  - Method names should encode their parameter's meaning (`fetchByBillingId`, not `fetch($billingId)`) so the call site is unambiguous without IDE help.
  - Avoid vague verb names like `process` — they signal you don't know what the method does.
  - Watch for method names that lie: `findUserById` that secretly accepts an email is a name lying about its parameters.
- **Canonical code example (PHP):**
```php
// Before
public function scopeRecent($query, $carbon) {
    return $query->where('created_at', $carbon);
}

// After
public function scopeSubscribedOn($query, $date = null) {
    $date = $date ?: Carbon::today()->subWeek();
    return $query->where('created_at', $date);
}
```
- **Sources:** Play With Confidence [08:00–09:00]; Drop Down a Level [13:14]; No Abbreviations [04:43, 07:10].

### Don't repeat the receiver's noun in its own method name
- **Category:** Naming
- **One-line rule:** A method should not restate context the receiving object already supplies.
- **Why it matters:** When a class is wrongly named, every method has to re-state the missing context, producing 3- and 4-word method names like `addWatchLater`, `removeWatchLater`, `isWatchingLater` on a class called `UserProgress`. The verbose method names are diagnostic — the *class* is the real problem. Once you name the class for what it manages (`WatchLaters`), the methods collapse to single verbs (`add`, `remove`, `has`).
- **How to apply:**
  - When method names need 3+ words to be intelligible, rename the *class*, not the methods.
  - On a `Order` class, define `ship()`, not `shipTheOrder()`.
  - On a collection-shaped class, prefer the conventional verb set: `add`, `remove`, `has`, `toggle`, `get`, `flush`.
  - For boolean queries, use `has(...)` on a collection-like class rather than `is...()` constructions.
  - Don't shorten so far that you produce ungrammatical names (`is(...)` alone won't read).
- **Canonical code example (PHP):**
```php
// Before
$user->watchLaters()->addWatchLater($video);
$user->watchLaters()->isWatchingLater($video);

// After  (class renamed UserProgress -> WatchLaters)
$user->watchLaters()->add($video);
$user->watchLaters()->has($video);
```
- **Sources:** Choose Your Class Names Wisely [00:00–06:43]; No Abbreviations [07:38].

### Keep names short — two words is the target
- **Category:** Naming
- **One-line rule:** Aim for ≤ 2-word names; when a name needs more, ask first whether the unit is doing too much.
- **Why it matters:** When you can't describe a method in two words, the method is probably doing too much. The awkward name is a signal to refactor, not a license to invent `prepAndShipAndNotifyUser` or fall back to a vague verb like `process`.
- **How to apply:**
  - Treat the rule as a smell detector, not a hard cap — `fetchByBillingId` is fine.
  - Conjunctions in names ("And", "Or") are red flags for multiple responsibilities.
  - Falling back to `process` or `handle` to dodge the word count is a bigger smell than a long name.
- **Sources:** No Abbreviations [05:43–07:10].

### Avoid boolean flags in public APIs
- **Category:** Functions and methods
- **One-line rule:** Don't expose `bool` parameters that switch behavior — extract a second method whose name encodes the variant.
- **Why it matters:** Six months later a reader sees `mute($kate, false)` and has no idea what `false` means; they have to dig into the method body to recover the meaning. Booleans on public APIs require every caller to remember the convention. A second named method (`muteTemporarily`) self-documents at the call site.
- **How to apply:**
  - Pause before adding any boolean parameter and ask "could a second named method remove the need?"
  - Extract a sibling method whose name encodes the variant (`muteTemporarily`, `cancelImmediately`).
  - When the new method would mostly duplicate the old, have it delegate to the original and pass through what differs (e.g. an `$attributes` array, not another flag).
  - Drive the refactor from the test side: change tests to call the desired API first, then make production code match.
- **Canonical code example (PHP):**
```php
// Before
public function mute(User $muted, $permanent = true) {
    if ($permanent) {
        $this->mutedAccounts()->attach($muted);
    } else {
        $this->mutedAccounts()->attach($muted, ['expires_at' => now()->addWeek()]);
    }
}

// After
public function mute(User $muted, $attributes = []) {
    return $this->mutedAccounts()->attach($muted, $attributes);
}

public function muteTemporarily(User $muted) {
    return $this->mute($muted, ['expires_at' => now()->addWeek()]);
}
```
- **Sources:** Avoid Flags [02:18–05:47]; Coding on the Fly [17:35]; Improve Confusing Code With Small Refactors [08:18].

### Don't use `else`
- **Category:** Control flow
- **One-line rule:** Eliminate the `else` keyword by returning early, throwing, or letting fall-through handle the second case.
- **Why it matters:** Every branch is another path the reader must trace on every read. When the `if` branch already returns, `else` is structural noise. Stacked conditionals force readers to hold every path in their head simultaneously.
- **How to apply:**
  - If the `if` branch ends with `return`, drop the `else` and let the second branch fall through unindented.
  - Order branches as failure-first / happy-path-last: invert predicates (`passes()` → `fails()`) so early returns sit at the top.
  - Convert wrapping `if (good) { ... } else { throw; }` into a leading `if (bad) { throw; }` guard.
  - Keep `if/else` only when the symmetry genuinely aids readability ("if X do this, otherwise do that").
  - Use `abort_if($cond, 403, $msg)` over manual `if ($cond) abort(403)`.
- **Canonical code example (PHP):**
```php
// Before
if (Date::today() != 'Friday') {
    if ($validator->passes()) {
        Post::create($input);
        return Redirect::home();
    } else {
        return Redirect::back()->withInput()->withErrors($validator);
    }
} else {
    throw new Exception('We do not work on Fridays.');
}

// After
if (Date::today() == 'Friday') {
    throw new Exception('We do not work on Fridays.');
}

if ($validator->fails()) {
    return Redirect::back()->withInput()->withErrors($validator);
}

Post::create($input);
return Redirect::home();
```
- **Sources:** Don't Use `else` [00:00–03:42]; Sweat the Small Stuff [05:41]; Coding on the Fly [16:15].

### Cap method bodies at one level of indentation
- **Category:** Control flow
- **One-line rule:** Treat any method with more than one level of indentation as a refactor signal.
- **Why it matters:** Indentation depth is a concrete proxy for complexity. Each `if` inside an `if` doubles the number of execution paths. Visual depth (the "Flying V" — indentation that ramps up and back down) is the strongest signal that code wants to break apart. Decreasing indentation is "nearly always an indication that you're on the right track."
- **How to apply:**
  - Work from the inside out: zone in on the deepest nested block first and extract outward.
  - Collapse `if (A) { if (B) { ... } }` into `if (A && B) { ... }` when the inner block is the only thing the outer guards.
  - Replace nested logic with `array_filter` / `array_map` (or language equivalents) when the loop's intent matches a built-in primitive.
  - Use early-return to flatten guard conditions.
  - Use the squint test: scan the file half-closed and let dense regions pop out as next refactor targets.
- **Canonical code example (PHP):**
```php
// Before
public function filterBy($accountType) {
    $filtered = [];
    foreach ($this->accounts as $account) {
        if ($account->type() === $accountType) {
            if ($account->isActive()) {
                $filtered[] = $account;
            }
        }
    }
    return $filtered;
}

// After
public function filterBy($accountType) {
    return array_filter($this->accounts, function ($account) use ($accountType) {
        return $account->isOfType($accountType);
    });
}
```
- **Sources:** One Level of Indentation [00:06–11:55]; Improve Confusing Code With Small Refactors [05:58, 07:11]; Beware the Flying V Complication [19:08].

### Tell, don't ask
- **Category:** Encapsulation and data design
- **One-line rule:** Push predicates and decisions onto the object that owns the data; don't pull state out and decide outside.
- **Why it matters:** When callers ask `type()` and `isActive()` and assemble the answer themselves, the object's fields leak into every consumer. Move the question onto the object (`isOfType($type)`) and the getters can become private — better information hiding, fewer consumers entangled with internal shape. The controller shouldn't decide *how* a user is invited; it should say "team, invite this user" and let the model branch.
- **How to apply:**
  - When two getters always combine to answer a higher-level question, move that question onto the class.
  - Once predicates move onto the class, demote the previously public getters to private.
  - "Drop down a level" — push behavior decisions from controllers down to models.
  - Avoid "helicopter parent" callers that reach into another object's fields and orchestrate its work; ask the object to do it.
- **Canonical code example (PHP):**
```php
// Before — caller assembles the answer
if ($account->type() === 'savings' && $account->isActive()) { /* ... */ }

// After — object answers the question
if ($account->isOfType('savings')) { /* ... */ }
```
- **Sources:** One Level of Indentation [10:13–11:18]; Drop Down a Level [02:36, 03:28]; Refactoring for Clarity [02:31, 05:55].

### Encapsulate raw column updates behind expressive model methods
- **Category:** Encapsulation and data design
- **One-line rule:** Wrap multi-attribute updates in a domain-named method on the model so the call site reads as intent.
- **Why it matters:** `$user->update(['stripe_active' => 1, 'stripe_plan' => 'forever', ...])` in a controller leaks DB schema into the orchestration layer. `$user->upgradeToLifetime()` says what the operation *means*; the column list is contained inside the model where it belongs.
- **How to apply:**
  - Replace inline `$model->update([...])` with verbs from the domain (`redeemedBy($user)`, `upgradeToLifetime()`, `cancelImmediately()`).
  - The method body owns the column list; callers own the intent.
  - Prefer a static finder (`GiftCertificate::byKey($key)`) over scattering `where('key', ...)->firstOrFail()` everywhere.
- **Canonical code example (PHP):**
```php
// Before
$certificate->update(['redeemed' => true, 'redeemer_id' => $user->id]);

// After — method on the model
public function redeemedBy($user) {
    $this->update(['redeemed' => true, 'redeemer_id' => $user->id]);
}
// Call site
$certificate->redeemedBy($user);
```
- **Sources:** Coding on the Fly [14:40, 19:06]; Refactoring for Clarity [02:31].

### Replace primitives with domain objects at method boundaries
- **Category:** Encapsulation and data design
- **One-line rule:** Pass richer types across method boundaries when the callee would otherwise have to re-resolve or branch on a primitive.
- **Why it matters:** A method that accepts an email string and then has to "is this a known user?"-branch every call is doing work that belongs upstream. Pass a `User` instance (real or unsaved) and the method works with one type instead of two.
- **How to apply:**
  - Use `firstOrNew(['key' => $value])` to collapse find-or-construct branches into one expression.
  - Use Eloquent's `exists` property to test "has this been persisted?" rather than null-checking a separately fetched record.
  - Keep call-site simplicity in mind — the goal is a richer type *if* it removes branching, not richness for its own sake.
- **Canonical code example (PHP):**
```php
// Before — callee branches on string-vs-known
public function invite($email) {
    $user = User::where('email', $email)->first();
    if (!$user) { $user = new User(['email' => $email]); }
    // ...
}

// After — caller hands in a User; firstOrNew collapses both paths
public function invite(User $user) { /* one path */ }

$user = User::firstOrNew(['email' => $email]);
$team->invite($user);
```
- **Sources:** Drop Down a Level [03:46–05:18].

### Wrap primitives only when they earn it
- **Category:** Encapsulation and data design
- **One-line rule:** Wrap a primitive only when it brings clarity, has behavior, requires self-validation, or is an important domain concept.
- **Why it matters:** Reflexively wrapping every string and int is "very likely the worst case scenario" — adds complexity without payoff. But a bare `cache($data, 50)` is genuinely ambiguous (hours? minutes? seconds?), and a value like `EmailAddress` that owns its own validation guarantees consistency at the type level.
- **How to apply:**
  - Apply the four-criteria checklist: clarity at the call site, behavior to attach, validation/self-consistency, important domain concept.
  - Make value objects immutable: state-changing methods `return new static(...)` rather than mutating `$this`.
  - For unit-bearing values (seconds, weights), make the constructor `private` and expose `fromX(...)` named constructors per unit; pair with `inX()` accessors.
  - Consider extending the API as an alternative — `workoutForHours($n)` and `workoutForMinutes($n)` may beat introducing a new type.
  - Don't promote incidental scalars (`$name`, simple labels) — leave them as primitives.
- **Canonical code example (PHP):**
```php
class TimeLength {
    private function __construct(protected $seconds) {}

    public static function fromHours($hours) {
        return new static($hours * 3600);
    }
    public static function fromMinutes($minutes) {
        return new static($minutes * 60);
    }
    public function inSeconds() { return $this->seconds; }
}

// Call site is unambiguous about units
$john->workoutFor(TimeLength::fromHours(3));
$john->workoutFor(TimeLength::fromMinutes(45));
```
- **Sources:** Wrap Primitives (Sometimes) [00:00–12:25].

### A method should return one type
- **Category:** Functions and methods
- **One-line rule:** Don't return a union type from a method — pick one and persist the other as a side effect.
- **Why it matters:** A `Team::invite()` that returns either `User` or `Invitation` pushes branching onto every caller. Normalize to one return type; if there's another object to surface, persist it as a side effect or expose it via a separate accessor.
- **How to apply:**
  - When you find yourself returning either `A` or `B`, persist the `B` as a side effect and return `A` (or vice versa).
  - Implementations of an interface must return the same shape — if one returns `array` and another returns `Collection`, normalize inside the implementation (`->toArray()`), not at the call site.
  - `instanceof` / `is_a` on a value returned through an abstraction is a refactor signal.
- **Canonical code example (PHP):**
```php
// Before — caller has to branch
$result = $team->invite($user); // User OR Invitation

// After — always returns User; Invitation is a side effect
public function invite(User $user) {
    if (!$user->exists) {
        Invitation::create(['email' => $user->email, 'team_id' => $this->id]);
    }
    return $user;
}
```
- **Sources:** Drop Down a Level [22:13]; Liskov Substitution [05:15–08:50].

### Inline single-use locals and helpers
- **Category:** Functions and methods
- **One-line rule:** When a temporary variable or wrapper method is used exactly once and adds no name, inline it.
- **Why it matters:** A variable named once and used once immediately after is a name the reader has to track for no benefit. A private method that just delegates one line restates the call site. Drop the indirection — but not militantly: a temp variable that names a long expression earns its keep.
- **How to apply:**
  - Inline a temporary unless the inlined line becomes unreadably long.
  - If a private method has shrunk to one line that restates the call site, inline it.
  - Read the method body aloud — if a wrapper name and its body say the same thing, drop the wrapper.
  - Don't be militant: when an expression is dense, a named local is the readable choice.
- **Sources:** Sweat the Small Stuff [02:41]; Refactoring for Clarity [07:00, 09:40]; Improve Confusing Code With Small Refactors [41:02].

### Don't extract until you'd reuse it
- **Category:** Refactoring practice
- **One-line rule:** Promote inline code to a named helper, scope, or class only when reuse is real, not anticipated.
- **Why it matters:** Auto-extracting a query scope every time you see a `where`, or making a method "for clarity" that's used once, "litters" the file with one-off names. The noise compounds. Extract when the same shape appears in two real callers, or when the name genuinely encodes a chunk of logic.
- **How to apply:**
  - When swapping in a newly extracted helper, first delete the inline code and confirm tests go red, then swap and watch them go green — proves the assertion exercises that path.
  - Generalize a helper (e.g. `scopeOnPlan($plan)` from `scopeOnMonthly`) only when the rigid version's repetition is real.
  - Single-use methods are still fine when they *name* a chunk of logic — judgment, not a count threshold.
  - Defer abstraction until the simple version actually hurts.
- **Sources:** Play With Confidence [05:35, 05:03]; Be Strict With Your Controllers [14:40]; Is It Better? [17:15].

### Comments are a flashlight; remove them by making code self-describing
- **Category:** Naming
- **One-line rule:** A comment that points at unclear code is a TODO to rename or extract — once you do, delete the comment.
- **Why it matters:** Comments in a spike phase are flashlights — they point at code that wasn't clear when written. The fix is to make the next line self-describing (extract a function, rename a variable) and then remove the comment. A comment that just paraphrases the next line of code adds noise without value, and stale comments actively mislead.
- **How to apply:**
  - When tempted to add a comment explaining what a condition means, lift the condition into a well-named method whose name encodes the comment.
  - Keep comments that frame *intent* (the "why"); drop ones that restate *what* the next line does.
  - Stale comments are common in real projects — delete them rather than letting them lie.
  - When refactoring a spike, treat the existing comments as a TODO list of names to invent.
- **Canonical code example (PHP):**
```php
// Before — comment explains a compound condition
// Make sure the account is the right type and active
if ($account->type() === $type && $account->isActive()) { /* ... */ }

// After — extracted method name says what the comment said
if ($account->isOfType($type)) { /* ... */ }
```
- **Sources:** One Level of Indentation [06:25, 07:25]; Beware the Flying V Complication [16:11, 17:54]; Refactoring Insurance [11:10].

### Cover code with tests before refactoring
- **Category:** Testing
- **One-line rule:** Refactor only behind a green test suite.
- **Why it matters:** "Without those tests, it's simply too risky." Without a safety net, developers leave working-but-ugly code untouched indefinitely ("tucking the code away"). Tests buy you the right to play — every refactor becomes a click-of-a-button experiment.
- **How to apply:**
  - Run the full suite before starting any refactor; treat green as the precondition, not a goal.
  - Re-run after every micro-change; never batch unverified edits.
  - When a change goes red, revert to green before retrying — don't pile fixes onto a broken baseline.
  - Never begin a *new* refactor while existing tests are red — fix the red baseline first.
  - When the safety net isn't tests (e.g. live animation), refactor in tiny steps and verify in the browser between each step.
- **Sources:** Refactoring Insurance [00:00–12:22]; Play With Confidence [00:00–17:09]; Improve Confusing Code With Small Refactors [01:07–34:25]; Drop Down a Level [17:51]; Is It Better? [02:09]; Beware the Flying V Complication.

### Tests prove only what they assert
- **Category:** Testing
- **One-line rule:** Tighten assertions on the parts that matter — replace `Mockery::any()` and broad matchers with specific argument expectations.
- **Why it matters:** A test mocking `createCoupon` with `Mockery::any()` will pass even if the discount is silently changed from 10% to 99%. The test only proves what it asserts; loose matchers let behavioral regressions slip through.
- **How to apply:**
  - Use `Mockery::on(fn ($arg) => ...)` to assert argument shape; avoid `Mockery::any()` for values that matter.
  - Add control fixtures who should NOT receive the side effect (a user from a different month, or on a different plan); asymmetric tests catch over-broad queries.
  - Always pair a positive fixture with at least one negative.
  - Always pass an explicit count to `Mail::assertSent(..., n)` so over-sending fails too.
  - Prove a test has teeth by deliberately commenting out the production code and watching it fail.
- **Sources:** Play With Confidence [00:13–00:56]; Refactoring Insurance [10:02–12:07]; Coding on the Fly [20:29].

### Test behavior, not implementation
- **Category:** Testing
- **One-line rule:** Drive feature tests through HTTP endpoints and assert observable outcomes; don't assert "calling X sets property Y."
- **Why it matters:** Behavior tests survive refactors — you can extract a service class later and the tests stay green without modification. Implementation-coupled tests force you to update the test every time you reshape the code, defeating the safety-net purpose. Browser-driver form tests cost more than they pay back; POSTing to the endpoint is faster and tests the same thing.
- **How to apply:**
  - Hit the endpoint with `$this->post(...)`, then assert with `assertDatabaseHas`, `Mail::assertQueued`, attribute checks after redirection.
  - Mock collaborators sparingly — they couple tests to implementation; legitimate refactors then break tests for the wrong reasons.
  - Use spies (`Mockery::spy` + `$this->swap`) when you need to assert exact interactions, but ask first whether asserting the outcome would do.
  - Mock external services (Stripe, Mail) by default to keep tests fast; only a small minority should hit real APIs.
- **Canonical code example (PHP):**
```php
public function it_generates_a_gift_certificate_upon_payment() {
    $this->post('/gift-certificates', [
        'stripeToken' => $this->createStripeToken(),
        'stripeEmail' => 'foo@example.com'
    ]);

    $this->assertDatabaseHas('gift_certificates', [
        'purchaser_id'    => User::latest()->value('id'),
        'amount_received' => '25000'
    ]);
}
```
- **Sources:** Coding on the Fly [21:55–23:00]; Refactoring Insurance [04:04, 09:00]; Play With Confidence [00:56].

### Be strict with your controllers
- **Category:** Architecture and module shape
- **One-line rule:** Stick to the seven RESTful actions; when a non-RESTful verb tempts you, extract a new controller.
- **Why it matters:** Compound action names like `storeMember`, `leaveTeam`, `inviteMember` are the symptom of a second resource hiding inside the controller. Splitting into `TeamMembersController` returns each action to a single-word RESTful verb (`store`, `destroy`, `invite`) and keeps every controller's surface small and predictable.
- **How to apply:**
  - The rule is: don't abandon `index`, `show`, `create`, `store`, `edit`, `update`, `destroy`.
  - Prefer a new controller over a service class as the first refactor move; service-class extraction is the next rung.
  - When a verb doesn't fit CRUD, name the new controller `<Subject><Verb>sController` (e.g. `GiftCertificateRedemptionsController`).
  - Don't fear an Eloquent query in a controller — extract only when the query repeats; promote to a static method on the model when it does.
  - Single-use methods are still fine when they name a chunk of logic.
- **Canonical code example (PHP):**
```php
// Before — compound actions
class TeamsController {
    public function storeMember()   { /* ... */ }
    public function destroyMember() { /* ... */ }
    public function inviteMember()  { /* ... */ }
}

// After — second controller; verbs collapse
class TeamMembersController {
    public function store()   { /* ... */ }
    public function destroy() { /* ... */ }
    public function invite()  { /* ... */ }
}
```
- **Sources:** Be Strict With Your Controllers [02:31–14:40]; Coding on the Fly [01:30].

### Sweat the small stuff
- **Category:** Refactoring practice
- **One-line rule:** Tiny tweaks compound — scan for what visually pops, take the cheap wins, then go deeper.
- **Why it matters:** No single small change matters; the cumulative effect defines the architecture and the shape of every future PR. Likened to credit card debt: no single purchase sinks you, the compound effect does. Don't plan one big refactor — stack many small ones, each cheap and reversible.
- **How to apply:**
  - First pass: scan for obvious — overly long lines, formatting inconsistencies, a comment over unclear code, a function inside a function for no reason.
  - Pick a convention (PSR-2, brace style) and follow it; consistency outweighs which convention you pick.
  - Use auto-formatters to enforce indentation/brace consistency.
  - Prefer the framework's newer/shorter API (`request('name')` over `$request->input('name')`, `$request->validate(...)` over `$this->validate(...)`).
  - Default to importing classes via `use` rather than inlining fully-qualified names.
  - Queue work the user shouldn't wait on (`Mail::queue` over `Mail::send`).
  - Move repeated literal values into config files rather than duplicating.
- **Sources:** Sweat the Small Stuff [00:00–12:37]; Improve Confusing Code With Small Refactors [34:25]; Refactoring for Clarity [09:49].

### Repeated method prefixes signal a missing class
- **Category:** Architecture and module shape
- **One-line rule:** When several methods on one class share a prefix, the prefix is the real method name and each suffix is its own class.
- **Why it matters:** `registerTeam`, `registerSubscriber`, `registerGuest` on a controller is a `if/else` ladder waiting to happen. Promote `register` to the method, turn each suffix into a strategy class implementing a shared contract, and the controller's `store` method collapses to: get strategy → call `handle()`.
- **How to apply:**
  - Name strategy classes verb + noun (`RegistersTeam`, `RegistersSubscriber`); never reuse the bare entity name (`Team`, `Subscriber`) — collides with models.
  - Strategies expose a single method, conventionally `handle` (matching framework idiom).
  - Define a shared interface (`RegistersUser`) so all strategies implement the same contract explicitly.
  - Hide selection behind a factory method (`getRegistrationStrategy`) — one place that maps input to concrete class.
  - Place strategies in a layer between controller and model — registration touches request, DB, mail, jobs.
- **Canonical code example (PHP):**
```php
// Before
class RegistrationsController {
    public function store() {
        if ($type === 'team')       { return $this->registerTeam(); }
        if ($type === 'subscriber') { return $this->registerSubscriber(); }
        if ($type === 'guest')      { return $this->registerGuest(); }
    }
}

// After — strategy + factory
interface RegistersUser {
    public function handle();
}
class RegistersTeam implements RegistersUser { public function handle() { /* ... */ } }

class RegistrationsController {
    public function store() {
        return $this->getRegistrationStrategy(request('type'))->handle();
    }
}
```
- **Sources:** The Strategy and Factory Patterns [02:00–07:18]; Don't Use `else` [05:29–08:35].

### Encapsulate user actions as use cases
- **Category:** Architecture and module shape
- **One-line rule:** Model each user action as a single class whose body is the ordered list of steps required to complete it.
- **Why it matters:** Spreading one logical action across model events and listeners "gets very indirect." A use case keeps the steps colocated and readable — one class, one navigable place that documents the whole flow.
- **How to apply:**
  - Use cases live in `app/UseCases/` and are named for the action verb + noun (`RegistersTeam`, `PurchaseVideo`).
  - Single public entry point named `handle` that lists the action's steps in order.
  - Each step is a private method named for what it does (`createUser`, `recordPayment`, `sendWelcomeEmail`).
  - Don't bake pattern names into method names — `getRegistrationStrategy` is implementation; `determineRegistrationMethod` is intent.
  - Steps can be chained as a fluent API when each returns `$this`.
  - Prefer one encapsulated use case over event/listener chains for a single logical action.
- **Canonical code example (PHP):**
```php
class RegistersTeam {
    public function handle($attributes) {
        return $this
            ->createUser($attributes)
            ->createTeam()
            ->recordPayment()
            ->sendWelcomeEmail();
    }
    private function createUser($attributes) { /* ... */ return $this; }
    private function createTeam()             { /* ... */ return $this; }
    private function recordPayment()          { /* ... */ return $this; }
    private function sendWelcomeEmail()       { /* ... */ return $this; }
}
```
- **Sources:** Encapsulated UseCases [00:26–05:18]; Refactoring for Clarity [11:35].

### Co-locate everything a feature needs
- **Category:** Architecture and module shape
- **One-line rule:** A feature's dependencies, configuration, and wiring should live in a single file or directory — not threaded through five.
- **Why it matters:** The pain isn't file count; it's fragmentation. When you can't answer "where is X configured?" with one location, the architecture is wrong regardless of how clean each individual file looks. A project-wide search for the feature name should hit one or two files, not five.
- **How to apply:**
  - Each feature is one class file in a dedicated directory; the file declares its dependencies and contributions.
  - Components return data; the framework decides what to do with it (don't mutate a passed-in config from inside the component).
  - Make optional hooks actually optional — implement only what the feature needs.
  - Provide an escape hatch (`webpackConfig(config)`) for the rare case a feature must mutate the host directly.
  - Validate refactors with a project-wide search for the feature name — if it still hits more than ~2 files, co-location hasn't been met.
  - Expose the same internal extension API to users (`mix.extend('foo', new FooComponent())`) — eat your own dog food.
- **Sources:** Component Refactor Reflections [00:37–11:25].

### Design the API before writing the implementation
- **Category:** Refactoring practice
- **One-line rule:** Sketch how a consumer will *call* the thing first; only then build to satisfy that interface.
- **Why it matters:** Skipping this step ships features that work but feel wrong to use, and by then it's too expensive to redesign. Designing object APIs by writing the call site first is also a key TDD/BDD benefit — redundancy and awkwardness get caught at the call site, not hidden in the class.
- **How to apply:**
  - Write the desired call site first; let it dictate the method name, parameters, and shape.
  - When refactoring a test API, change the test to call the desired API, watch it fail, then update production code to match.
  - "If you don't like writing the test, the code probably isn't well-designed."
- **Sources:** Component Refactor Reflections [04:39]; No Abbreviations [08:09]; Avoid Flags [03:20].

### Single Responsibility — one reason to change per class
- **Category:** Abstraction and polymorphism
- **One-line rule:** Each class should have exactly one reason to change.
- **Why it matters:** A class with multiple reasons to change is fragile and hard to maintain. A reporting class that does authorization, persistence, *and* HTML formatting will be edited every time any of those concerns changes. Extract each concern into its own class so that, e.g., a switch from MySQL to MongoDB only touches the repository.
- **How to apply:**
  - Heuristic: if you can name multiple distinct callers/concerns that would each force this class to change (persistence, formatting, auth), extract each.
  - Authorization is not a domain concern — keep `Auth::`-style calls out of reporting/domain classes; push them up to the controller.
  - Persistence belongs in a repository, injected via the constructor.
  - Don't bake output formatting into a domain class; either return raw data or accept a formatter.
  - Avoid generic `*Service` names — `RegisterUser` makes SRP violations obvious; `UserService` invites them.
- **Canonical code example (PHP):**
```php
class SalesReporter {
    public function __construct(SalesRepository $repo) {
        $this->repo = $repo;
    }
    public function between($start, $end, SalesOutputInterface $formatter) {
        $sales = $this->repo->between($start, $end);
        return $formatter->output($sales);
    }
}
```
- **Sources:** Single Responsibility [02:40–12:00]; Limit Your Instance Variables [04:36]; Is It Better? [15:01].

### Open/Closed — extend, don't modify
- **Category:** Abstraction and polymorphism
- **One-line rule:** Open entities for extension, closed for modification — adding a new variant should not require editing the consumer.
- **Why it matters:** Editing the same code repeatedly causes code rot and risks breaking working code. `instanceof` chains inside a calculator are a "dead ringer" you're modifying instead of extending. Extract the varying behavior to an interface, make concretes implement it, and have the consumer depend only on the interface — adding a triangle is a new class, not an edit.
- **How to apply:**
  - Type-checking branches (`instanceof`, `is_a`) inside a consumer are the canonical OCP smell.
  - Extract the varying behavior to an interface; have each concrete implement it.
  - Have the consumer depend on the interface and call one polymorphic method (`$shape->area()`).
  - Treat OCP as a goal, not an absolute rule — strive for it pragmatically.
- **Canonical code example (PHP):**
```php
// Before
public function calculate($shapes) {
    foreach ($shapes as $shape) {
        if ($shape instanceof Square) { $area[] = $shape->width * $shape->height; }
        elseif ($shape instanceof Circle) { $area[] = M_PI * $shape->radius ** 2; }
    }
    return array_sum($area);
}

// After
public function calculate($shapes) {
    foreach ($shapes as $shape) {
        $area[] = $shape->area();
    }
    return array_sum($area);
}
```
- **Sources:** Open-Closed [00:07–13:23]; Interface Segregation [05:00].

### Liskov Substitution — subclasses must honor the parent's contract
- **Category:** Abstraction and polymorphism
- **One-line rule:** A subclass cannot tighten preconditions or change the return shape of a method it overrides.
- **Why it matters:** That's the whole point of polymorphism — the consumer wrote against the parent's contract, and substitution is what makes "code to an interface" pay off. A subclass that throws on inputs the parent accepted, or returns a `Collection` where the interface promised `array`, silently breaks every consumer.
- **How to apply:**
  - Subclass overrides specialize behavior; never narrow inputs.
  - Implementations must produce the same return shape as the interface declares — normalize inside the implementation (`->toArray()`), not at the call site.
  - When the language can't enforce return types, use `@return` docblocks and hold implementers to them.
  - `instanceof` / `is_a` on a value returned through an abstraction is a refactor signal — fix the implementations, don't branch in the consumer.
- **Canonical code example (PHP):**
```php
interface LessonRepositoryInterface {
    /** @return array */
    public function getAll();
}

// Bad — returns Collection, breaks LSP
class DbLessonRepository implements LessonRepositoryInterface {
    public function getAll() { return Lesson::all(); }
}

// Good — normalizes to the contract's shape
class DbLessonRepository implements LessonRepositoryInterface {
    public function getAll() { return Lesson::all()->toArray(); }
}
```
- **Sources:** Liskov Substitution [01:09–09:38].

### Interface Segregation — many small interfaces beat one fat one
- **Category:** Abstraction and polymorphism
- **One-line rule:** Clients should never be forced to implement methods they don't use.
- **Why it matters:** Forcing an `AndroidWorker` to stub a `sleep()` method (returning `null`) is a code smell that signals the interface is doing too much. Fat interfaces violate SRP at the contract level. Many narrow single-method interfaces are explicitly preferred — and a class is allowed to implement several at once.
- **How to apply:**
  - Name interfaces by capability with `-able` + `Interface` suffixes (`WorkableInterface`, `SleepableInterface`).
  - Prefer single-method interfaces; even one is fine.
  - When a client must vary behavior across types, push the variation into the types via a new interface method (`beManaged()`); don't branch on type in the client.
  - Read every type hint as a coupling claim — ask "does this method actually need everything that type can do?"
- **Canonical code example (PHP):**
```php
interface WorkableInterface  { public function work(); }
interface SleepableInterface { public function sleep(); }
interface ManageableInterface { public function beManaged(); }

class HumanWorker implements WorkableInterface, SleepableInterface, ManageableInterface {
    public function work()  { /* ... */ }
    public function sleep() { /* ... */ }
    public function beManaged() { $this->work(); $this->sleep(); }
}

class AndroidWorker implements WorkableInterface, ManageableInterface {
    public function work()      { /* ... */ }
    public function beManaged() { $this->work(); } // no sleep() stub forced
}
```
- **Sources:** Interface Segregation [00:13–08:34].

### Dependency Inversion — depend on abstractions, not concretions
- **Category:** Abstraction and polymorphism
- **One-line rule:** Type-hint the abstraction the consumer needs, not the concrete class — and let the consumer own the abstraction.
- **Why it matters:** Dependency injection ≠ dependency inversion. Injecting a concrete `MySQLConnection` through a constructor still couples your `PasswordReminder` to MySQL. Both the high-level module and the low-level module should point at the same interface in the middle. The interface should be owned by the consumer (the outlet analogy: the house defines the outlet shape; the TV conforms).
- **How to apply:**
  - Type-hint constructor parameters with the abstraction (interface), never the concrete class.
  - Define the interface as the smallest contract the consumer actually needs.
  - Frame design questions as "knowledge": does this class actually need to *know* this detail?
  - Type-hinting a concrete class drags in transitive dependencies (`User extends Eloquent` means depending on `User` quietly depends on the entire ORM).
- **Canonical code example (PHP):**
```php
interface ConnectionInterface { public function connect(); }

class DbConnection implements ConnectionInterface {
    public function connect() { /* ... */ }
}

class PasswordReminder {
    public function __construct(private ConnectionInterface $connection) {}
}
```
- **Sources:** Dependency Inversion [00:11–08:14]; Interface Segregation [07:03–08:34]; Open-Closed [12:53].

### Limit instance variables (collaborators) per class
- **Category:** Encapsulation and data design
- **One-line rule:** Cap injected collaborators at around four; treat five+ as a smell that demands investigation.
- **Why it matters:** A constructor with seven dependencies is the canonical god-object signature — every collaborator was reasonable in isolation, the cumulative result is tangled responsibilities. Three specific class names are bloat magnets: `User`, `UsersController`, `UserService`.
- **How to apply:**
  - Count only object-typed properties (collaborators) — scalar fields don't count.
  - Funnel repository access through a service; controllers shouldn't talk to repositories directly when a service exists.
  - Split controllers along cohesive concerns (`AuthController` for register/cancel) rather than packing all user-adjacent actions into `UsersController`.
  - Replace cross-cutting collaborators (mailer, logger) with domain events + listeners when the work is a side effect.
  - Treat the cap as a smell, not a law — the rule's job is to make you look.
- **Sources:** Limit Your Instance Variables [00:14–09:19].

### Template Method — skeleton in the parent, hooks in the children
- **Category:** Abstraction and polymorphism
- **One-line rule:** When sibling classes share most of an algorithm, lift the skeleton to an abstract parent and declare the differing steps as `protected abstract` hooks.
- **Why it matters:** Copy-pasting between siblings and tweaking a few lines is the diagnostic signal. The shared algorithm wants to live in one place. `protected abstract` turns "subclass must implement" into a compile-time guarantee; making the template method `final` prevents subclasses from reshaping the workflow they're supposed to fill in.
- **How to apply:**
  - Refactor in two passes: first lift identical methods to the parent (plain inheritance), then lift the algorithm itself and convert the differing step into an abstract hook.
  - Name abstract hooks by their *role* in the algorithm, not by a specific subclass's value (`addPrimaryToppings`, not `addTurkey`).
  - Mark the public template method `final` once stable.
  - Build fluent step methods that `return $this` so the template reads as a chain.
- **Canonical code example (PHP):**
```php
abstract class Sub {
    final public function make() {
        return $this->layBread()->addLettuce()->addPrimaryToppings()->addSauces();
    }
    protected abstract function addPrimaryToppings();
    // shared steps live here
}

class TurkeySub extends Sub {
    protected function addPrimaryToppings() { /* turkey */ return $this; }
}
```
- **Sources:** The Template Method Pattern [00:07–13:18].

### Replace setTimeout pyramids with promises and async/await
- **Category:** Control flow
- **One-line rule:** Wrap a single `pause(ms)` Promise helper, mark callers `async`, and replace nested timers with sequential `await`s.
- **Why it matters:** Repeatedly reaching for `setTimeout`/`setInterval` causes increasing indentation and callback chaining. The mental model: a Promise is "call me when you're ready to come home." A while-loop with `await` flattens recursive timer chains into linear, readable code.
- **How to apply:**
  - Wrap `setTimeout` once in a Promise helper; never reach for it directly in app code.
  - Replace recursive timer chains with `while (cond) { await step(); }`.
  - Move sequencing methods onto the class that owns the data they operate on.
  - Don't double-wrap: `async` already returns a Promise — adding `new Promise(async (resolve) => ...)` around a body is noise.
- **Canonical code example (JavaScript):**
```js
function pause(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function swap() {
    await pause(2000);
    await heading.clear();
    await heading.type(choices[current - 1]);
    return swap();
}
```
- **Sources:** Beware the Flying V Complication [33:18–48:13].

### Be willing to revert
- **Category:** Refactoring practice
- **One-line rule:** Always ask "is it better?" — and if the answer is no, throw the refactor away.
- **Why it matters:** Refactoring can *feel* good (more files, more "patterns") while making the codebase harder to understand. SRP and OCP are not free — splitting into many tiny files where two inline closures used to be can hurt readability. Don't keep a refactor just because you spent time on it; sunk cost is not a reason to ship complexity. A `nah` alias (`git reset --hard && git clean -df`) makes reverting cheap.
- **How to apply:**
  - After any refactor, evaluate it explicitly against the simpler original: is it now better? More files is fine; more confusion is not.
  - Validate refactors objectively (search results, file count, "easier to reason about" check).
  - When introducing an abstraction (constructor injection, observers, events) is "kind of a wash," revert.
  - Defer abstraction until the simple version actually hurts — a couple of inline closures in `boot()` are fine until they aren't.
  - Treat SRP/OCP as goals, not automatic wins.
- **Sources:** Is It Better? [00:00–17:15]; Component Refactor Reflections [10:27–11:01]; Sweat the Small Stuff [09:46]; Play With Confidence [11:46]; Improve Confusing Code With Small Refactors [19:00].

### Pragmatism over perfection
- **Category:** Refactoring practice
- **One-line rule:** Ask "does it matter?" before optimizing structure — clean architecture is a spectrum, not a rule.
- **Why it matters:** When code is one-shot and rarely modified, mixing responsibilities, hard-coding a price, or catching a broad exception can be acceptable. Repository-behind-an-interface for every query "sounds great on paper" but if you've shipped without issue for five months, the abstraction wasn't needed. Over-engineering throwaway code is its own waste. Clarity beats architectural rules — when refactors collide with rules like SRP, pick the version that reads more clearly.
- **How to apply:**
  - Measure how often the code will change before extracting.
  - Validating an HTTP request in the controller is fine — push back on "models should validate themselves."
  - Hard-coding values is fine when *you* own the system and there's no campaign tooling; not fine when business users need to configure.
  - Don't reach for events + listeners for what is effectively four lines of code.
  - "There aren't any rules" — judgment beats dogma.
- **Sources:** Coding on the Fly [05:55–13:00]; Refactoring for Clarity [05:55, 11:35]; Avoid Flags [04:47]; Wrap Primitives (Sometimes) [00:00].

### Get the unfamiliar codebase running locally before reading any of it
- **Category:** Reading code
- **One-line rule:** Your first act on a foreign codebase is `git clone && install && run` — reading without a working app is guessing.
- **Why it matters:** A live app gives you the only reliable feedback loop while you read. You can `dd()` values, follow a real request, see what actually renders. Reading without running forces you to construct the system in your head from text alone — every assumption you make is unverified until the day you ship a wrong fix. The friction of bootstrapping (env vars, submodules, key generation) is normal, not a sign of bad code.
- **How to apply:**
  - Spend the bootstrap time before any reading time, even if it takes the morning.
  - When the README is incomplete, read `composer.json`, `package.json`, `.env.example`, and any `make`/`compose` files to fill the gaps.
  - If the project genuinely cannot run locally (legacy infra, missing creds), set up a sandbox or shadow environment before reading — don't read blind.
  - "Three things: learn, write code, and read code" — treat reading as a deliberate skill, not a side effect.
- **Sources:** Get it Running Locally [0:00–1:19].

### Read the entry-point routing file first
- **Category:** Reading code
- **One-line rule:** When entering an unfamiliar app, read the routing/index file first — it's the bird's-eye view of every surface the app exposes.
- **Why it matters:** Opening random files and guessing what they do is the slowest way to learn a codebase. The routes file (or its equivalent — URL config, controller registry, RPC schema) lists every entry point the system responds to. Once you've read it, every other file has a coordinate: which route reaches it. You're not just reading code; you're mapping the territory before you walk it.
- **How to apply:**
  - In a Laravel app, start with `routes/web.php` and `routes/api.php`. In an Express app, the `app.use()` calls. In a Vue/Nuxt app, the `pages/` directory.
  - For each route, follow the chain — route → controller method → service → model → view — once. Don't try to memorize everything; just thread a single request through end-to-end.
  - Skip pure marketing/static Blade views unless you have a specific UI question — they're rarely teaching anything new.
  - "This gives you a quick bird's eye view of what sort of things this application can do."
- **Sources:** Finding the Documentation Page [0:00–0:45].

### Trace unfamiliar globals, helpers, and middleware to their origin
- **Category:** Reading code
- **One-line rule:** When you see a global function, helper, or middleware you don't recognise, find where it's *registered* before assuming it's framework magic.
- **Why it matters:** Most "magic" turns out to be project-level glue: a helper file autoloaded via `composer.json`, a custom middleware in `Kernel.php`, a service provider binding. Mistaking custom for framework code sends you down the wrong documentation rabbit hole and makes you trust code you shouldn't have. The reverse — mistaking framework for custom — wastes hours reading vendor source when the docs would have answered in a minute.
- **How to apply:**
  - For an unknown global function, check `composer.json` autoload (`files`), `app/helpers.php`, and any `bootstrap/app.php` registrations.
  - For an unknown middleware, check `app/Http/Kernel.php` — framework middleware lives in `vendor/`; everything else is yours.
  - For a vendor package, go to its Packagist/GitHub README rather than reading vendor source — the project doc is the curated path.
  - Once you've classified the symbol (framework vs project vs vendor), the right reading strategy follows automatically.
- **Sources:** Parsing Markdown [0:00–1:30]; Full Page Caching [0:00–1:44].

### Verify your mental model with `dd()` at branch points
- **Category:** Reading code
- **One-line rule:** When reading code that branches on data, insert a `dd()` (or equivalent dump-and-die) at the branch point and load the page — confirm the actual value before believing your model.
- **Why it matters:** Reading code is hypothesis-forming; `dd()` is the experiment that confirms or refutes the hypothesis. A controller you thought returned `null` might return an empty `Collection`; a variable you assumed was a string might be a `Crawler` object. Without verifying, every downstream read inherits the wrong assumption — and the bug fix you ship will be based on a fantasy of how the code works.
- **How to apply:**
  - Drop `dd($variable)` at each branch you don't fully understand; load the page; read the output; remove the `dd()`.
  - When the value type itself is uncertain, `dd(get_class($x))` or `dd(gettype($x))` tells you the shape.
  - For non-web code, use `var_dump` / `print_r` / language-equivalent and run the unit test that exercises that path.
  - Don't leave `dd()` calls in committed code — they're for reading, not running.
- **Sources:** Rendering the Documentation [0:00–1:30, 3:30–4:15].

### Re-implement what you read with TDD to commit the lessons to memory
- **Category:** Reading code
- **One-line rule:** After reading a piece of code you want to learn from, re-implement it from scratch test-first — the red/green cycle exposes which parts you actually understood.
- **Why it matters:** Reading produces the illusion of understanding; building reveals the gaps. TDD-driving the re-implementation forces every behaviour into an executable assertion, which catches the misread assumptions you would have shipped silently. The goal is not deployable code — it's making the patterns stick.
- **How to apply:**
  - Pick a bounded subsystem (a router, a cache layer, a markdown renderer), close the original, and rebuild it test-first.
  - Distinguish high-level feature tests (HTTP request → expected response) from unit tests on a specific class; pair them.
  - When a test needs filesystem or external state, use a partial mock to stub just the boundary method rather than reproducing infrastructure.
  - Discard the re-implementation when done — its value was learning, not shipping.
- **Sources:** Make Your Own Documentation Website with TDD [0:33–1:00].

### Remove dead code on sight
- **Category:** Naming
- **One-line rule:** Delete commented-out code, unreachable branches, and abandoned options — every line a human reads must justify itself by running.
- **Why it matters:** Dead code carries the same cognitive weight as live code on every read, with none of the value. Commented-out blocks force readers to wonder "is this coming back?" Unreachable branches (the `break` after `return`, the feature-flagged code that always evaluates one way) make tests harder to reason about. Abandoned code — options arrays whose keys are never consumed, methods nothing calls — is the most insidious because it looks alive. Git history is the archive; the working tree is for code that runs.
- **How to apply:**
  - Trust version control: deleted code is recoverable from `git log -p`.
  - Use static analysis (PHPStan, Psalm, IDE inspections) to find unreachable branches automatically.
  - For genuinely "we'll need this next quarter" code, add a TODO with a date and a ticket, not an inert commented block.
  - When you find an options key with no consumer, grep for it across the codebase before deleting — and delete if no callers exist.
  - The "Leave the codebase better than you found it" rule applies here most directly.
- **Sources:** Remove Dead Code [4:38–6:32]; Leave the Codebase Cleaner Than You Found It [5:33–5:49].

### Apply a code style automatically with a shared tool
- **Category:** Naming
- **One-line rule:** Formatting is not a personal habit — pick one tool (Pint, Prettier, gofmt) with one preset, commit the config, and let CI enforce it.
- **Why it matters:** Manual or IDE-only formatting drifts across teammates and across editors. Style debates are pure overhead — once a project picks a preset, every keystroke spent on indentation or brace placement is wasted attention that could go to substance. A repository-level config (`pint.json`, `.prettierrc`) plus a CI gate makes the style invisible: it just happens.
- **How to apply:**
  - Commit a `pint.json` (Laravel) / `.prettierrc` / `.editorconfig` at the repo root with the chosen preset.
  - Add the formatter to CI as a `--check` gate that fails the build on drift.
  - Add a pre-commit hook (or rely on the CI gate) — don't rely on humans to remember to format.
  - The choice of preset (PSR-12 vs Laravel vs Symfony) matters less than picking *one*. Resist arguing about it after the initial choice.
  - "You're not really being a programmer, you're being a typist" — automation reclaims the attention.
- **Sources:** Apply a Code Style [0:07–0:51].

### Four or more parameters signal a missing class
- **Category:** Functions and methods
- **One-line rule:** When a method accepts four or more arguments, treat it as a signal that a class is hiding in that parameter list — extract a Strategy/DTO/Driver that owns those values together.
- **Why it matters:** Parameters that travel together describe one concept. When you pass `($files, $destination, $type, $customCompressor)` to `compress()`, the four arguments are really one *compression job* — and the function probably has an `if ($type === 'css')` branch inside that's a second smell pointing at the same missing class. Extracting the cluster into a concrete class (`JavaScriptDriver`, `CSSDriver`) replaces the parameters and the branches with one polymorphic dispatch. This is the distinct Laracasts framing — **not the "≤2 params" rule from Robert Martin's *Clean Code* book**, which this catalog does not adopt. The threshold here is four; the response is "extract a class," not "shrink the count."
- **How to apply:**
  - Four-or-more is a smell, not a hard limit. Three with a boolean is often worse than four with no boolean.
  - When you find the cluster, look for the *internal branch* in the method body — that's usually the polymorphism candidate.
  - Each extracted strategy/driver holds its own parameters as constructor properties and implements a shared interface (or matches the contract via duck-typing).
  - If you find yourself splitting into more methods rather than a class hierarchy, that's also valid — pick whichever resolves the smell more cleanly.
  - "When a function or a method accepts four arguments or more, that might be an indication that there's a missing class."
- **Canonical code example (PHP):**
```php
// Before
function compress($files, $destination, $type, $customCompressor) {
    if ($type === 'css') { /* CSS-specific minify */ }
    if ($type === 'js')  { /* JS-specific minify  */ }
    // ...
}

// After — missing class extracted
interface CompressionStrategy { public function fire(): void; }

class JavaScriptDriver implements CompressionStrategy {
    public function __construct(private array $files, private string $destination) {}
    public function fire(): void { /* JS minify */ }
}

class CSSDriver implements CompressionStrategy { /* ... */ }

function compress(CompressionStrategy $strategy): void {
    $strategy->fire();
}
```
- **Sources:** Too Many Method Parameters is a Sign [02:11–03:00].

### Return a typed default, not `null`
- **Category:** Functions and methods
- **One-line rule:** When a function might legitimately return "no result," return a typed empty value (`[]`, `''`, an empty collection, a Null Object) — not `null`.
- **Why it matters:** Every `null` return propagates up the call stack as a guard requirement. Two `null`-returning functions chained without guards crash; with guards, the caller's code doubles in size as it null-coalesces every step. Returning `[]` instead of `null` from a function whose contract is "list of things" means callers can `foreach` directly, with zero null checks. Tony Hoare called null his "billion dollar mistake" — the fix is to return the right empty type, not propagate the absence.
- **How to apply:**
  - For functions returning a collection, return `[]` (or an empty `Collection`) instead of `null`.
  - For functions returning a string, return `''` instead of `null` (when the empty string makes semantic sense — sometimes it doesn't).
  - When the absence carries meaning, pair this with a Null Object: a class that implements the same interface and provides safe defaults (see "Use a Null Object to eliminate auth/presence checks").
  - Some platform functions (e.g. `preg_replace`) genuinely return `null` on error — keep guards for those at the boundary; don't let nulls leak deeper.
  - Auditing for this on a real codebase has been measured at ~30% code shrinkage by deleting the now-unneeded guards.
- **Canonical code example (PHP):**
```php
// Before
function recentTweetsFor(User $user): ?array {
    if (!$user->hasTweets()) return null;
    return $this->fetch($user);
}
// Caller
$tweets = $service->recentTweetsFor($user);
if ($tweets !== null) {
    foreach ($tweets as $tweet) { /* ... */ }
}

// After
function recentTweetsFor(User $user): array {
    if (!$user->hasTweets()) return [];
    return $this->fetch($user);
}
// Caller
foreach ($service->recentTweetsFor($user) as $tweet) { /* ... */ }
```
- **Sources:** Reasonable Returns [2:41–3:20].

### Default method visibility to `protected` or `private`
- **Category:** Encapsulation and data design
- **One-line rule:** Mark every method `protected` (or `private`) unless it's deliberately part of the public API — and prefer getters over public properties so you can intercept reads later.
- **Why it matters:** Public is the most permissive visibility; once a property or method is public, every caller can read or write it, and you've lost the right to intercept that access without breaking call sites. Starting from `protected` and elevating to `public` only on purpose means your public surface area is intentional, not accidental. The benefit cashes in months later when you need to mask an email, validate a write, or rename an internal field — and the only file you have to change is the class itself.
- **How to apply:**
  - Constructor + the deliberate public methods are `public`. Everything else starts `protected`.
  - Default to `protected` over `private` if you want subclasses to retain access; default to `private` if you prefer strict isolation. Pick one team-wide and be consistent.
  - For properties that the outside world should be able to read, expose a getter (`getEmail()`) — that one line of indirection preserves your future flexibility.
  - In PHP 8.4+, see "Use property hooks and asymmetric visibility" for a way to keep public-property ergonomics without losing interception.
  - "When you hide internals, you are better protecting the consistency and integrity of your objects."
- **Sources:** Encapsulation and Visibility [16:29–20:55].

### Use capability interfaces (`CanBeLiked`, not `Likeable`)
- **Category:** Encapsulation and data design
- **One-line rule:** Name interfaces after what a class *can do* (capability), not what it *is* (type) — and type-hint against the capability so any class that signs the contract is admitted.
- **Why it matters:** A type-shaped interface (`NewsletterProvider`) describes membership in a hierarchy; a capability interface (`CanBeLiked`, `Sortable`, `Cacheable`) describes one specific behaviour a class has agreed to support. Capability interfaces compose freely: one class can implement `CanBeLiked` + `Cacheable` + `Sortable` without any awkward "is a" relationship. Type-hinting `handle(CanBeLiked $model)` instead of `handle(Comment|Post|Thread $model)` means adding a new type requires zero changes to the consumer.
- **How to apply:**
  - Name capability interfaces with a verb or adjective phrase: `CanBeLiked`, `Reportable`, `Sortable`, `Subscribable`.
  - Keep them narrow — one capability per interface (the ISP principle reinforces this).
  - Use them as type hints in functions that consume the capability, not just as bag markers.
  - PHP duck-typing works too (no interface, just matching method names), but the interface gives IDE autocomplete and immediate errors when a class accidentally omits a required method.
  - The pattern matches Rust traits, Go interfaces, Swift protocols — it's not a PHP idiom, it's a general OO discipline.
- **Canonical code example (PHP):**
```php
// Before
function handle(Comment|Post $model): void { /* like logic */ }
// Adding Thread requires editing this signature

// After
interface CanBeLiked {
    public function like(): void;
    public function isLiked(): bool;
}

class Comment implements CanBeLiked { /* ... */ }
class Post    implements CanBeLiked { /* ... */ }
class Thread  implements CanBeLiked { /* ... */ }

function handle(CanBeLiked $model): void { /* like logic — never changes */ }
```
- **Sources:** Interfaces as Feature Filters [08:23–11:30].

### Compose, don't inherit, for cross-cutting concerns
- **Category:** Encapsulation and data design
- **One-line rule:** When a class needs vendor-specific or cross-cutting behavior (billing, mailing, geolocation), extract that behavior into a collaborator class, inject it as a dependency, and depend on its abstraction — never inherit it in or mix it via a trait.
- **Why it matters:** Inheriting `Subscription extends StripeBilling` (or `use StripeBillingTrait`) bakes Stripe into your domain class forever. The day you switch to Braintree, every consumer of `Subscription` is affected. Composing the relationship — `Subscription` has-a `BillingPortal` interface, with `StripeBillingPortal` and `BraintreeBillingPortal` as implementations — means swapping providers is one ServiceProvider binding change. The consuming class doesn't know or care which provider is in use, which is precisely what "decoupled" means.
- **How to apply:**
  - Apply the "is-a" test: `Subscription` is-a `Billing` is false; therefore composition, not inheritance.
  - Create an interface that names the *capability you need* (`BillingPortal`), implement it per vendor (`StripeBillingPortal`), inject the interface.
  - Don't create the interface speculatively — wait until you have at least two concrete implementations (or a tested isolated mock).
  - If a class accumulates more than ~5 injected collaborators, decompose it further — composition without bounds creates its own god object.
  - Traits in PHP look like composition but compile to inheritance — same coupling risk. Use them sparingly and for true *capability mixins*, not for vendor integration.
  - "It doesn't know that we work with Stripe because it doesn't care. It's none of its business."
- **Sources:** Understanding Object Composition and Abstractions [13:34–17:00].

### Use property hooks and asymmetric visibility (PHP 8.4+)
- **Category:** Encapsulation and data design
- **One-line rule:** In PHP 8.4+, replace getter/setter method pairs with property hooks (`get` / `set` blocks on the property declaration) and use asymmetric visibility (`private(set)`) to keep public readability with private writability.
- **Why it matters:** The historical pattern — `private $email` + `getEmail()` + `setEmail($e)` with validation inside — is four moving parts for one concept. Property hooks collapse it to a single declarative block on the property itself. Asymmetric visibility removes the second category of boilerplate: read-only-from-outside fields no longer need a hand-rolled getter. The net effect is the *encapsulation discipline* (start `protected`, expose intentionally, intercept reads/writes) without the *visual noise* that used to make people skip it.
- **How to apply:**
  - Requires PHP 8.4. For codebases still on 8.3, skip this principle or polyfill via the existing getter/setter pattern.
  - Arrow shorthand (`get => strtolower($this->email)`) is interchangeable with the brace form for one-liners.
  - `private(set)` on a `public` property is the canonical "publicly readable, internally writable" pattern.
  - Validation goes inside the `set` block — same as it would have lived inside `setEmail()`.
  - Don't reach for this when the property is genuinely just a public bag (no validation, no transformation, no future interception) — bare public is still fine for DTOs.
- **Canonical code example (PHP):**
```php
// Before (PHP ≤ 8.3)
class User {
    private string $email;
    public function getEmail(): string { return $this->email; }
    public function setEmail(string $email): void {
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            throw new InvalidArgumentException('Invalid email');
        }
        $this->email = $email;
    }
}

// After (PHP 8.4+)
class User {
    public string $email {
        get => $this->email;
        set {
            if (!filter_var($value, FILTER_VALIDATE_EMAIL)) {
                throw new InvalidArgumentException('Invalid email');
            }
            $this->email = $value;
        }
    }
    // Or, read-only from outside:
    public private(set) string $id;
}
```
- **Sources:** From Getters and Setters to Property Hooks [06:20–12:08].

### Prefer constructor property promotion (PHP 8.0+)
- **Category:** Abstraction and polymorphism
- **One-line rule:** Declare typed properties inline in the constructor signature — don't write a separate `private $x;` + assignment in the body.
- **Why it matters:** The pre-PHP-8 pattern (property declaration, then re-typed parameter, then `$this->x = $x;`) is three gestures expressing one concept. Promotion makes it one. Less code at the boundary makes constructors with several dependencies actually readable, which makes Dependency Injection visible at a glance and harder to skip. This is pure syntactic sugar with no behavioural difference — but the readability gain compounds across a codebase with hundreds of classes.
- **How to apply:**
  - Use promotion for every constructor parameter that maps directly to a property. Mix promoted and non-promoted parameters freely.
  - Add visibility (`public`, `protected`, `private`) and type to each promoted parameter — that's what triggers the promotion.
  - Pair with `readonly` (PHP 8.1+) for properties that should never be reassigned after construction.
  - The non-promoted form is still valid and not deprecated — don't refactor existing code for the sake of it; apply on new classes and at natural touch points.
- **Canonical code example (PHP):**
```php
// Before
class Subscription {
    private BillingPortal $billing;
    private LoggerInterface $logger;
    public function __construct(BillingPortal $billing, LoggerInterface $logger) {
        $this->billing = $billing;
        $this->logger = $logger;
    }
}

// After
class Subscription {
    public function __construct(
        private readonly BillingPortal $billing,
        private readonly LoggerInterface $logger,
    ) {}
}
```
- **Sources:** Objects [08:24–09:30].

### Use typed DTOs instead of associative arrays for multi-field data
- **Category:** Abstraction and polymorphism
- **One-line rule:** When a data shape has more than one field and travels across method boundaries, define a DTO class — never pass associative arrays around.
- **Why it matters:** An associative array is the original unsafe primitive: any caller can omit a key, mistype a key, or invent extra keys, and PHP won't notice until runtime (often *deep* into the call stack, far from the caller who got it wrong). A typed DTO class with constructor-promoted properties gives you IDE autocomplete, PHPStan/Psalm static enforcement, and the constructor itself becomes the documentation of which fields are required. This is the distinct sibling of "Wrap primitives sometimes" — that principle covers single values; this one covers *shapes*.
- **How to apply:**
  - Any time you reach for `['key' => $value, …]` to pass into a function — define a `Song`, `Order`, `Address` DTO and pass an instance instead.
  - Use constructor property promotion + `readonly` to keep DTOs tiny: `public function __construct(public readonly string $name, public readonly Artist $artist) {}`.
  - For collections of DTOs, document the array type with a PHPDoc annotation: `/** @param Song[] $songs */` — PHPStan/Psalm enforce the contract that PHP itself can't (PHP lacks native generics as of 2026).
  - DTOs are pure data + minimal behaviour. If a DTO grows methods that *do things* (not just transform/format), promote it to a domain object.
  - Don't reach for a DTO for a single-field value — that's the "wrap primitives only when they earn it" principle's territory.
- **Canonical code example (PHP):**
```php
// Before
function addSong(array $song): void {
    // Is 'name' required? 'artist'? What if 'durationMinutes' is missing?
    $this->songs[] = $song;
}
$album->addSong(['name' => 'My Heart Will Go On', 'artist' => 'Celine Dion']);

// After
final class Song {
    public function __construct(
        public readonly string $name,
        public readonly string $artist,
        public readonly int $durationSeconds,
    ) {}
}

/** @param Song[] $songs */
function addSongs(array $songs): void { /* ... */ }

$album->addSongs([
    new Song(name: 'My Heart Will Go On', artist: 'Celine Dion', durationSeconds: 280),
]);
```
- **Sources:** DTOs, Types, and Static Analysis [04:37–07:01].

### Reach for a named extraction pattern when refactoring fat classes
- **Category:** Architecture and module shape
- **One-line rule:** When a controller, model, or service is doing too much, the fix usually has a named pattern — pick the right one from the catalog below rather than ad-hoc splitting.
- **Why it matters:** Refactors fall apart when "extract a class" leaves you staring at an empty file with no idea what to put in it. The Laracasts refactoring corpus is largely a catalogue of *named* patterns — each one a recognised shape with a clear before/after. Knowing the catalogue means you skip the "where do I even start" phase and go directly to "this is a Policy extraction" or "this is a View Model extraction." Naming the pattern also lets you communicate the refactor — "let's pull this into a Use Case" is a one-line PR description.
- **How to apply:** Match the symptom in your code to a pattern in the catalogue:

| Symptom | Pattern | What it does |
|---|---|---|
| Controller has 10+ validation rules + persistence in one method | **Form Object** | Class owns `rules()` + `persist()`; controller calls `$form->save()` |
| Controller method orchestrates 4–6 steps for one user action | **Use Case** (or self-handling Command/Job) | Single class with `handle()`; controller delegates entirely |
| Controller has multiple side effects after a create (email, CRM, log) | **Domain Event** + **Listeners** | Model fires past-tense event (`UserRegistered`); listeners each handle one side effect |
| Controller has 3+ `abort(403)` guard clauses at the top | **Policy** | Authorization class with one method per action; `$this->authorize($model)` invokes it |
| `User` model has 8+ methods sharing a prefix (`favoritesCount`, `experiencePoints`, …) | **Pass-Through** | `User::stats()` returns `new Stats($user)`; methods move to `Stats` |
| `User` model has 5+ unrelated method groups (forum, completions, etc.) | **Single-use Trait** | Extract each group to `Completable`, `ParticipatesInForum`; `User` `use`s them |
| A primitive accumulates methods (`revenue()`, `revenueInDollars()`, …) | **Value Object via Accessor** | `getRevenueAttribute()` returns `new Revenue($value)` with the formatters |
| Method body is one big `handle()` doing 10+ heterogeneous steps | **Tasks-as-Steps array** | `$tasks = [DoThis::class, AddFooToBar::class, …]`; loop and call `->handle()` |
| Method body is one big `if/elseif` for variants of the same operation | **Strategy + Factory** | Each branch becomes a Strategy class with shared interface; factory picks the right one |
| Value needs several validation/transformation steps before use | **Normalize-via-static-constructor** | `Coupon::normalize($code)->against($plan)` consolidates checks; returns Null Object on miss |
| Long, important Eloquent query inline in controller | **Query Object** | Dedicated class with `static get()`; one-line call from controller |
| Third-party API returns raw arrays littering templates | **Wrap third-party** | `collect($feed)->map(fn($i) => new Podcast($i))`; domain class owns formatting + URL |
| Behaviour should be optional/stackable on an existing class | **Decorator** | Wraps the original class, conforms to its interface, delegates after adding behaviour |
| API call chain reads more naturally as `$x->visit()->see()->notSee()` | **Fluent Interface** | Each method returns `$this` (or compatible object) for chaining |

- Pick the pattern that matches the smell most precisely; don't force a pattern that's "close enough."
- All patterns share the same goal: move behaviour to where it belongs, keep each class focused on one thing.
- Most patterns above are demoed in Way's "Whip Monstrous Code Into Shape" series — consult that series for end-to-end refactor walk-throughs.
- "These pattern names maybe help describe what it does. But at the end of the day, it's a class."
- **Sources:** Consider Form Objects [01:30–02:23]; Consider Use Cases [07:01–08:35]; Consider Domain Events [04:12–05:00]; God Object Cleanup #1: Pass-Through [02:24–04:03]; God Object Cleanup #2: Traits and Socks [02:29–05:26]; God Object Cleanup #3: Value Objects [02:18–04:38]; Consider Policies [02:29–04:58]; Consider Splitting Tasks into Steps [02:16–03:55]; Consider Strategizing [04:34–07:47]; Consider Normalizing [05:14–06:06]; Consider Query Objects [01:48–02:59]; Consider Wrapping it Up [00:46–02:20]; Consider Decorating [04:40–05:31]; Consider Fluent Interfaces [00:39–03:37].

### Refactor views with the same discipline you give classes
- **Category:** Architecture and module shape
- **One-line rule:** Treat templates as code — extract repeating markup into partials, pass scoped data to them, and use **dynamic partial names** to replace `if/elseif` on type.
- **Why it matters:** A 400-line `home.blade.php` or 400-line Vue SFC carries the same maintenance cost as a 400-line class — but somehow we let it slide. The same extraction discipline applies: long sections become partials (`@include('pages.home.header')` / `<Header />`), repeating loop bodies become reusable item partials with passed variables, and conditional includes based on type become a single dynamic include (`@include('statuses.' . $status->type)`) — which means adding a new type creates a new partial file and zero edits to the calling template.
- **How to apply:**
  - Section extraction: any group of markup that has a clear conceptual identity (header, sidebar, feature list) becomes a partial.
  - Repeated list-item extraction: if you render a "series card" in 3 templates, extract once and `@include('series.card', ['series' => $s])`.
  - Dynamic partial naming: replace `@if($status->type === 'video') ... @elseif($status->type === 'text') ... @endif` with `@include('statuses.' . $status->type)` — adding a new status type is one new file, no edits to the dispatch site.
  - Pass scoped data explicitly to each partial; use null-coalesce for optional defaults (`$width ?? 'col-3'`).
  - In Vue/React projects: the same principle applies. Extract child components for sections; use `<component :is="...">` for the dynamic-include pattern.
  - "Give your views the same importance and the same respect that you would show any other class within your project."
- **Sources:** Consider Refactoring Your Views [09:37–11:10].

### Use a Null Object to eliminate presence/auth checks at the call site
- **Category:** Architecture and module shape
- **One-line rule:** Replace `if (auth()->check())` (or `if ($x !== null)`) sprawl by always providing an object — a `GuestUser`, an `AnonymousAccount`, an empty `Cart` — that implements the same interface and returns safe defaults.
- **Why it matters:** When views and services are dotted with `@if(auth()->check())` wrappers, every call site is defensive. The fix is to never let `null` reach the call site in the first place: bind `$user = auth()->user() ?? new GuestUser()`, and templates can call `$user->isSubscribed()` unconditionally because `GuestUser::isSubscribed()` returns `false`. The pattern eliminates an entire class of bug ("forgot to wrap in auth check") and dramatically simplifies templates.
- **How to apply:**
  - Identify the "absence" — guest user, empty cart, missing record — that's forcing call-site checks.
  - Create a class that implements the same interface (or extends the same base class) but returns safe defaults for every method.
  - Wire it in once at the boundary: `view()->share('user', auth()->user() ?? new GuestUser())`, or in a model accessor (`getCartAttribute() ?? new EmptyCart()`).
  - For chained calls that might encounter nulls mid-chain, return `new static()` (the Null Object) from the chain method itself.
  - This pairs naturally with "Return a typed default, not null" — both are aspects of the same anti-null discipline.
  - Don't overdo it: only worth the Null Object class if the call-site checks are widespread, not for one-off optional fields.
- **Canonical code example (PHP):**
```php
// Before
@if(auth()->check())
    @if($user->isSubscribed())
        <a href="/account">Account</a>
    @else
        <a href="/upgrade">Upgrade</a>
    @endif
@else
    <a href="/login">Log in</a>
@endif

// After
// AppServiceProvider boot()
view()->share('user', auth()->user() ?? new GuestUser());

// GuestUser.php
class GuestUser extends User {
    public function isSubscribed(): bool { return false; }
    public function name(): string { return 'Guest'; }
    // ... safe defaults for every method called in templates
}

// Template (no auth check needed)
@if($user->isSubscribed())
    <a href="/account">Account</a>
@else
    <a href="/upgrade">Upgrade</a>
@endif
```
- **Sources:** Consider a Guest User Class [05:37–07:44].

### Use the three-step process to refactor big blocks
- **Category:** Refactoring practice
- **One-line rule:** When facing a fat method, **label the reading level → add comments to identify sub-blocks → ask two questions of each sub-block** ("can this be done in a native way?" and "does this belong at this reading level?").
- **Why it matters:** Big blocks fail to refactor because there's nowhere obvious to start. The three-step process is a deterministic algorithm: labelling the reading level (controller vs model vs collaborator) tells you *which level of abstraction the method should be operating at*; comments identify the seams; the two questions force a concrete decision per sub-block. "Native way" finds replacements you forgot existed (use `array_filter` instead of `foreach`); "belong at this level" finds the sub-blocks that need to migrate down to the model.
- **How to apply:**
  - Step 1: Label what reading level you're at — "this is a controller; controllers orchestrate, they don't compute."
  - Step 2: Add `// 1. Detect role` / `// 2. Decide redirect` / `// 3. Apply` style comments above each sub-block. The comments are temporary scaffolding.
  - Step 3: For each commented sub-block, ask:
    - "Is there a native way to do this?" (Laravel collection method, PHP built-in, framework helper)
    - "Does this work belong at this reading level?" (if no, push it down — usually to the model)
  - Refactor is a "shell game" — code moved out must land somewhere readable; reducing the original to one line only helps if the new home is also clean.
  - Delete the scaffolding comments once the refactor lands. Their job is done.
- **Sources:** Break Up Big Blocks [11:43–12:41].

### Write pseudo-code for the ideal call first, then make it real
- **Category:** Refactoring practice
- **One-line rule:** When you can see the duplication but not the abstraction, write the call site you wish you had as a comment, then build the method or model behaviour to make that pseudo-code work.
- **Why it matters:** Refactoring backwards (poking at the existing code, hoping a shape emerges) is slow and prone to dead ends. Starting from the ideal call (`Course::enroll($user)`) forces you to declare what the cleanest API would look like; then the work becomes "make the system produce that API," which is much more directed. It also catches the wrong abstraction early: if your pseudo-code reads awkwardly, the abstraction is wrong before you've written any real code.
- **How to apply:**
  - Open the would-be call site as a comment: `// Course::enroll($user);`
  - Walk down: does that call site read naturally? If yes, build it. If no, iterate the pseudo-code first.
  - Common forms: a static constructor (`Order::placedBy($user)`), a fluent chain (`$user->subscribe()->to($plan)`), a single delegation (`$user->redirectToDashboard()`).
  - Pair with the proximity rule and the two-questions process — pseudo-code is the *target*; the other techniques are the path.
  - Don't just relocate code: each sub-block must itself be refactored so it earns its new home.
- **Sources:** Chapter Review (Big Blocks Demo) [8:30–9:30].

### Apply the proximity rule before refactoring a loop
- **Category:** Refactoring practice
- **One-line rule:** Before refactoring a loop, move every variable used inside the loop to immediately above the loop — once everything's adjacent, the loop's actual intent usually becomes obvious enough to replace with a native function.
- **Why it matters:** Loops are hard to read when their inputs are scattered across the surrounding scope. Moving the loop's variables right next to it puts the entire computation in your field of view; suddenly you can see "this is just filtering by date" or "this is just summing a field," and the replacement (`array_filter`, `array_sum`, `Collection::pluck()`) becomes a one-line fix. The proximity move is mechanical; the recognition is automatic once you've done the move.
- **How to apply:**
  - Step 1: Identify the loop you want to refactor. Step 2: Move every variable referenced inside the loop to the lines immediately above. Step 3: Re-read.
  - Common simplifications that pop out: `foreach + push` → `array_map`, `foreach + conditional push` → `array_filter`, `foreach + accumulator` → `array_sum`/`array_reduce`, `foreach + return on match` → `array_filter() + first` or `Collection::firstWhere()`.
  - When the loop body is one line after proximity, you're almost always one native function away from removing the loop entirely.
  - Familiarity with PHP's built-in array functions and Laravel Collections is a prerequisite — keep a reference open while learning the patterns.
  - Goal is readability, not line count: a one-line `array_filter(... callback ...)` is better than a four-line `foreach` only if the intent is clearer.
- **Sources:** Chapter Review (Proximity Rule Demo) [0:50–2:18].

### Apply the Rule of Three before extracting an abstraction
- **Category:** Refactoring practice
- **One-line rule:** Defer abstraction decisions until the third occurrence of a pattern — two data points are not enough to predict the third correctly; three are.
- **Why it matters:** DRY taken literally produces premature abstractions that match two cases and then break on the third — at which point you're stuck with an abstraction that's worse than the duplication. Sandi Metz: "duplication is far cheaper than the wrong abstraction." Waiting for the third occurrence means you have enough information to see the real pattern, not the pattern you guessed from two cases. The rule trades a small amount of short-term duplication for a large amount of long-term correctness.
- **How to apply:**
  - On the *second* occurrence, leave both copies in place. Note them mentally (or add a TODO if the code is hot enough that you'll definitely see it again).
  - On the *third* occurrence, you have three data points — look for the genuine commonality across all three and extract.
  - Don't read this as "never refactor on two" — it's "slow down on two." When the two cases are *identical* (literally the same characters), extracting is safe. When they differ in non-trivial ways, wait.
  - The rule directly tensions with DRY. That tension is intentional — DRY is a value, not a law.
  - The first abstraction you reach for is usually wrong; the third occurrence reveals the right shape.
  - "It wasn't until we had three data points that we were accurately able to predict the fourth."
- **Sources:** Rule of Three [2:22–3:26].

### Pursue symmetry at three levels (syntactic, semantic, systemic)
- **Category:** Refactoring practice
- **One-line rule:** Kent Beck's "the same idea expressed the same way everywhere it appears" — operates at three levels: **syntactic** (same code structure), **semantic** (same vocabulary), **systemic** (same design patterns).
- **Why it matters:** Symmetric code is predictable code — a reader who's seen one part of the system can guess what the next part looks like. Asymmetry has the opposite effect: every method that uses a slightly different naming convention or structure forces a fresh read. The three levels stack: syntactic symmetry (consistent formatting, consistent guard-clause structure), semantic symmetry (consistent verbs and nouns — `read/create/update/delete`, not `fetch/save/modify/remove`), and systemic symmetry (consistent design patterns — when the codebase uses Repository, every data access goes through Repository, not half through Eloquent direct).
- **How to apply:**
  - **Syntactic:** group guard clauses at the top, use the same call form for similar operations (all method calls, or all property accesses — not mixed), align return statement shapes.
  - **Semantic:** establish a domain vocabulary and stick to it. A repository's methods are `read/create/update/delete`, not `fetch/save/modify/remove`. A class named `tally()` for incrementing a count is more symmetric with sibling methods `input()` and `output()` than `incrementCount()` would be.
  - **Systemic:** when the codebase has a Strategy pattern for X, new variants of Y that fit the same shape should also be Strategies, not freelance classes. "Pattern bingo" — forcing a pattern that doesn't fit — is its own asymmetry.
  - Check symmetry by asking: "Can a reader predict what's next from anywhere in the codebase?"
  - Symmetry is *relative* — what's symmetric in one codebase may not be in another. Don't import a foreign codebase's idioms.
  - Iterate names: getting `timeToRecheck` instead of `readyToRerun` took several passes — the right name is the one that matches the surrounding vocabulary.
- **Sources:** Symmetry [0:07–0:34]; Chapter Review (Symmetry Demo) [11:32–12:08].

### Scratch refactor for 30 minutes to learn unfamiliar code
- **Category:** Refactoring practice
- **One-line rule:** When you inherit incomprehensible legacy code, spend ≤30 minutes "scratch refactoring" — rename freely, extract aggressively, restructure without caring if it runs — then **throw it all away**.
- **Why it matters:** Scratch refactoring (Martin Fowler's term) is a learning technique, not a refactor technique. The act of moving the code around forces you to confront every assumption it embeds; the act of throwing the result away keeps you honest about whether the rewrite was actually better, and keeps the technique low-risk. The understanding you build during the scratch pass *sticks* — when you then implement the real refactor (or just the feature you came to add), you do it with a working mental model instead of guesses.
- **How to apply:**
  - Set a hard timer: 30 minutes. The whole point is exploration, not delivery.
  - On a throwaway branch (or even just in your editor with no save), rename variables to what they should be called, extract methods, reorganise the file structure.
  - Don't worry about whether the code compiles, runs, or passes tests — that's not what scratch refactoring is for.
  - When the timer is up, `git stash drop` (or close the editor without saving) — and start the real implementation with the understanding you built.
  - This pairs with characterization tests (see below): scratch refactor reveals shape, characterization tests reveal behaviour, sprout/wrap apply the real change.
- **Sources:** Consider Scratch Refactoring [03:07–04:15].

### Use Sprout and Wrap to extend legacy code surgically
- **Category:** Refactoring practice
- **One-line rule:** **Sprout** — write new functionality as a clean tested class elsewhere and call it from a single new line in the legacy code. **Wrap** — rename the legacy method `*Legacy`, create a new same-named method that calls the legacy one plus clean pre/post actions.
- **Why it matters:** Adding another branch to a god class makes the god class worse; never refactoring legacy means it stays untouchable forever. Sprout and Wrap (Michael Feathers, *Working Effectively with Legacy Code*) are the surgical middle path: extend functionality without modifying the legacy class internals, in a way that the new code is fully testable in isolation. They're not heroic refactors — they're the disciplined small steps that compound into a clean codebase over time.
- **How to apply:**
  - **Sprout** — when you need a new behaviour: write `WiseProcessor implements PaymentProcessorInterface` with its own tests; in the legacy class, add one line: `$this->processors[TYPE_WISE] = new WiseProcessor()`.
  - **Wrap** — when you need to add behaviour around an existing method: rename `processPayment()` to `processPaymentLegacy()` (leave its guts untouched). Create a new `processPayment()` that calls `InvoiceService::create()`, then `$this->processPaymentLegacy()`, then `InvoiceService::markPaid()`.
  - Pair both with characterization tests as the safety net — you need to know the legacy method's actual behaviour before you wrap it.
  - These techniques are *tactical* — they slow the growth of the legacy mess but don't eliminate it. The strategic refactor (extracting the whole class) still needs to happen, just on a longer timeline.
  - The temptation to "just add another case" is strongest under deadline pressure — that's exactly when sprout/wrap pay off most.
- **Canonical code example (PHP):**
```php
// Wrap example
class Payment {
    // OLD method, renamed but untouched
    private function processPaymentLegacy($order) { /* original guts */ }

    // NEW wrapper — clean pre/post around the legacy call
    public function processPayment($order) {
        $invoice = InvoiceService::create($order);
        $result = $this->processPaymentLegacy($order);
        InvoiceService::markPaid($invoice);
        return $result;
    }
}
```
- **Sources:** Sprout and Wrap [03:24–03:57]; Extending Code That Wasn't Designed for Extensibility [00:31–01:19].

### Don't overdo SOLID
- **Category:** Refactoring practice
- **One-line rule:** SOLID is a toolset, not a goal — if applying it makes the codebase *harder* to navigate, simplify; the right unit of "single responsibility" is a domain concept, not an individual operation.
- **Why it matters:** Mechanically applied SOLID produces 4-file-hops to change a single form field: ServiceProvider → WireService → WireRepositoryInterface → AppServiceProvider. That's not maintainable code — it's ceremony masquerading as architecture. The actual goal is *navigability and adaptability*; SOLID is one tool among many for getting there. For a project with one payment provider and no plans for more, a single concrete class is more maintainable than the full interface + binding + factory dance — the abstraction earns its keep only when you *use* it for what abstractions exist to do (swap implementations, mock in tests).
- **How to apply:**
  - Ask "how do I expect this code to change?" before reaching for an interface. If the answer is "I expect to swap providers" — extract. If the answer is "we'll always have one of these" — don't.
  - The right unit of SRP is a *domain concept* (payment management, user onboarding), not a method-level operation (validate, transform, persist as three separate classes).
  - When you've applied SOLID and changing a field now requires 4 file hops, simplify back. The structural purity isn't worth the navigation cost.
  - The reverse failure is real too: skipping SOLID where it actually helps (swappable providers, testable services) buys short-term simplicity at long-term cost.
  - "Any design principle you choose should make it simpler for you to read, understand, manage, and extend your code." If it doesn't, it's not earning its keep.
  - This is the practical sibling of "Pragmatism over perfection" (#35) — applied specifically to SOLID rather than to architecture in general.
- **Sources:** Don't Overdo SOLID [05:38–06:24].

### Use characterization tests on legacy code before changing it
- **Category:** Testing
- **One-line rule:** When changing untested legacy code, write a test that *asserts what you assume the code does*, run it, let the failure teach you the real behaviour, then keep the (now correct) test as your safety net.
- **Why it matters:** Michael Feathers' *Working Effectively with Legacy Code* technique. You cannot safely refactor or extend code you don't understand, and reading alone produces false confidence. A characterization test treats the code as a black box: assert what you *think* the output is, run it, and the failure becomes documentation of what the code *actually* does. After a few iterations the test is green and you have an executable specification you can refactor against. The test wasn't there to verify behaviour you'd already specified — it was the *tool* for discovering behaviour.
- **How to apply:**
  - Name the test for the input scenario, not the expected output: `testProcessSuccessfulWirePayment` (you're describing the *call*, not the *behaviour*).
  - Assert your assumption explicitly. Run the test. Read the failure.
  - Each failure teaches you one thing the code actually does (e.g., "BankAPI rejects SWIFT codes shorter than 11 characters"). Update the assertion. Repeat.
  - For view-returning code, use snapshot testing — the snapshot *is* the characterization.
  - These tests hit the real database — set up a dedicated `_test` database; don't mock the DB out (mocked tests miss the failures that matter).
  - When the test is green, you have a safety net. *Now* you can refactor, extend, or wrap.
  - "The purpose of this is to demonstrate that you know nothing about the expected behavior of this piece of code."
- **Sources:** How to Test Untestable Code [00:00–01:16]; Leverage Seams to Add New Functionality to Existing Code [00:00–00:48].

### Extract a factory method to create a seam for mocking
- **Category:** Testing
- **One-line rule:** When legacy code creates dependencies inline (`new BankAPI()`), extract a tiny factory method (`createBankAPI()`) — that one extraction lets you subclass-and-override the dependency in tests without restructuring the class.
- **Why it matters:** Inline `new X()` calls make a class untestable in isolation — there's no way to swap the dependency without changing production code. The full refactor (dependency injection through the constructor) is often a large blast radius across all callers. Extracting a protected factory method is the *minimal* change that creates the seam: production behaviour is identical (still calls `new BankAPI()`), but tests can subclass the class, override the factory method to return a mock, and isolate the unit. This is the surgical version of DI — the same testability benefit at a fraction of the disruption.
- **How to apply:**
  - Find the `new X()` call inside the method you want to test. Extract it to `protected function createX(): X { return new X(); }`. Replace the call with `$this->createX()`.
  - In the test, declare `class TestableSubject extends Subject { protected function createX(): X { return $this->mock; } }`. Use `TestableSubject` in tests.
  - This is a *seam* — a Michael Feathers term for "a place where you can change behaviour without editing in place."
  - For new code, use proper constructor injection. This technique is for legacy code where DI refactor is too costly.
  - Pair with characterization tests: extract the seam → write a characterization test using the seam → safely refactor.
  - Once the seam is in place, *full* DI is a smaller next step — you can promote the factory method into a constructor dependency at any time.
- **Canonical code example (PHP):**
```php
// Before — untestable
class Payment {
    public function processWire($order) {
        $bank = new BankAPI();   // hard-coded — cannot mock
        return $bank->send($order);
    }
}

// After — seam extracted
class Payment {
    public function processWire($order) {
        $bank = $this->createBankAPI();
        return $bank->send($order);
    }
    protected function createBankAPI(): BankAPI {
        return new BankAPI();
    }
}

// Test
class TestablePayment extends Payment {
    public function __construct(private BankAPI $mock) {}
    protected function createBankAPI(): BankAPI { return $this->mock; }
}
```
- **Sources:** Leave the Codebase Cleaner Than You Found It [05:33–05:49].

## Cross-cutting themes

- **Constants beat literals** — the magic-numbers principle, the "wrap primitives sometimes" principle, and the "don't pass booleans" principle are all the same idea: a value the reader has to decode at the call site is worse than a name. Replace numbers with named constants, ambiguous units with named constructors, and boolean flags with second-named methods.
- **Objects beat primitives at boundaries** — passing a `User` instead of an email string, an `EmailAddress` instead of a validated string, a `Subscription` instance instead of a `'monthly'`/`'forever'` discriminator. Each replaces branching at the call site with polymorphism on the type.
- **The right owner runs the show** — most refactors come down to moving a decision to where the data lives: tell-don't-ask (predicates onto the model), drop-down-a-level (controllers delegate to models), encapsulated use cases (a single class owns the action), helicopter-parent avoidance (the model invites, the controller doesn't orchestrate fields).
- **Tests are the safety net that buys all of this** — every speaker treats refactoring without a green suite as off-limits. Tests prove what they assert (so tighten matchers and add control fixtures), tests should describe behavior (so endpoint-test, don't implementation-test), and a green suite is the precondition for "play."
- **Indirection has a cost** — the same speakers who teach Strategy, Factory, Template Method, and SOLID also teach: don't extract until you'd reuse, inline single-use helpers, throw the refactor away if it isn't better. The principles are tools, not goals; "is it better?" is the only real test.
- **Names are the front door of clarity** — bad class names cascade into bad method names; long method names hint at over-stuffed methods; comments-as-flashlights point at code that wants a name; don't repeat the receiver's noun. Almost every refactor in this corpus passes through renaming as a step.
- **Symmetry — the same idea expressed the same way everywhere it appears** — operates at three levels: syntactic (consistent code structure, consistent guard-clause grouping), semantic (consistent vocabulary — `read/create/update/delete`, not `fetch/save/modify/remove`), systemic (consistent design patterns — when the codebase uses Repository, every data access goes through Repository). Symmetric code is predictable code; a reader who's seen one part can guess the next. Asymmetry forces a fresh read on every method.
- **Reading is half the job** — before changing code, understand it the way the author did. The reading-code discipline (bootstrap-first, route-first, trace-to-origin, verify-with-`dd()`, re-implement-with-TDD) is not separate from refactoring practice; it's the precondition for safe refactoring. Reading without a working app is guessing, and refactors based on guesses ship as bugs.
