final class Ai68Json {
  const Ai68Json._();

  static Map<String, dynamic> object(Object? value, String name) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw FormatException('Expected $name to be an object');
  }

  static List<dynamic> array(Object? value, String name) {
    if (value is List) {
      return value;
    }
    throw FormatException('Expected $name to be an array');
  }

  static String string(Object? value, String name) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('Expected $name to be a non-empty string');
  }

  static String? optionalString(Object? value) {
    if (value == null) return null;
    return value.toString();
  }

  static int integer(Object? value, String name) {
    final parsed = optionalInteger(value);
    if (parsed == null) {
      throw FormatException('Expected $name to be an integer');
    }
    return parsed;
  }

  static int? optionalInteger(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double? optionalDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static bool boolean(Object? value) {
    return value == true || value == 1 || value == '1';
  }

  static List<String> strings(Object? value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList(growable: false);
  }
}

final class Ai68GuestConfig {
  const Ai68GuestConfig({
    required this.isEmailVerify,
    required this.isInviteForce,
    required this.isCaptcha,
    required this.captchaType,
    required this.emailWhitelistSuffixes,
    this.tosUrl,
    this.recaptchaSiteKey,
    this.recaptchaV3SiteKey,
    this.recaptchaV3ScoreThreshold,
    this.turnstileSiteKey,
    this.appDescription,
    this.appUrl,
    this.logoUrl,
  });

  factory Ai68GuestConfig.fromJson(Map<String, dynamic> json) {
    final suffixes = json['email_whitelist_suffix'];
    return Ai68GuestConfig(
      isEmailVerify: Ai68Json.boolean(json['is_email_verify']),
      isInviteForce: Ai68Json.boolean(json['is_invite_force']),
      isCaptcha: Ai68Json.boolean(json['is_captcha']),
      captchaType: Ai68Json.optionalString(json['captcha_type']) ?? 'recaptcha',
      emailWhitelistSuffixes: suffixes is List
          ? Ai68Json.strings(suffixes)
          : const [],
      tosUrl: Ai68Json.optionalString(json['tos_url']),
      recaptchaSiteKey: Ai68Json.optionalString(json['recaptcha_site_key']),
      recaptchaV3SiteKey: Ai68Json.optionalString(
        json['recaptcha_v3_site_key'],
      ),
      recaptchaV3ScoreThreshold: Ai68Json.optionalDouble(
        json['recaptcha_v3_score_threshold'],
      ),
      turnstileSiteKey: Ai68Json.optionalString(json['turnstile_site_key']),
      appDescription: Ai68Json.optionalString(json['app_description']),
      appUrl: Ai68Json.optionalString(json['app_url']),
      logoUrl: Ai68Json.optionalString(json['logo']),
    );
  }

  final bool isEmailVerify;
  final bool isInviteForce;
  final bool isCaptcha;
  final String captchaType;
  final List<String> emailWhitelistSuffixes;
  final String? tosUrl;
  final String? recaptchaSiteKey;
  final String? recaptchaV3SiteKey;
  final double? recaptchaV3ScoreThreshold;
  final String? turnstileSiteKey;
  final String? appDescription;
  final String? appUrl;
  final String? logoUrl;
}

final class Ai68RegisterRequest {
  const Ai68RegisterRequest({
    required this.email,
    required this.password,
    this.inviteCode,
    this.emailCode,
    this.recaptchaData,
    this.recaptchaV3Token,
    this.turnstileToken,
  });

  final String email;
  final String password;
  final String? inviteCode;
  final String? emailCode;
  final String? recaptchaData;
  final String? recaptchaV3Token;
  final String? turnstileToken;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'email': email,
      'password': password,
      if (inviteCode != null) 'invite_code': inviteCode,
      if (emailCode != null) 'email_code': emailCode,
      if (recaptchaData != null) 'recaptcha_data': recaptchaData,
      if (recaptchaV3Token != null) 'recaptcha_v3_token': recaptchaV3Token,
      if (turnstileToken != null) 'turnstile_token': turnstileToken,
    };
  }
}

final class Ai68CaptchaTokens {
  const Ai68CaptchaTokens({
    this.recaptchaData,
    this.recaptchaV3Token,
    this.turnstileToken,
  });

  final String? recaptchaData;
  final String? recaptchaV3Token;
  final String? turnstileToken;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (recaptchaData != null) 'recaptcha_data': recaptchaData,
      if (recaptchaV3Token != null) 'recaptcha_v3_token': recaptchaV3Token,
      if (turnstileToken != null) 'turnstile_token': turnstileToken,
    };
  }
}

final class Ai68User {
  const Ai68User({
    required this.email,
    required this.transferEnableBytes,
    required this.banned,
    required this.remindExpire,
    required this.remindTraffic,
    required this.balanceCents,
    required this.commissionBalanceCents,
    this.lastLoginAt,
    this.createdAt,
    this.expiredAt,
    this.planId,
    this.discount,
    this.commissionRate,
    this.telegramId,
    this.uuid,
    this.avatarUrl,
  });

  factory Ai68User.fromJson(Map<String, dynamic> json) {
    return Ai68User(
      email: Ai68Json.string(json['email'], 'user.email'),
      transferEnableBytes:
          Ai68Json.optionalInteger(json['transfer_enable']) ?? 0,
      banned: Ai68Json.boolean(json['banned']),
      remindExpire: Ai68Json.boolean(json['remind_expire']),
      remindTraffic: Ai68Json.boolean(json['remind_traffic']),
      balanceCents: Ai68Json.optionalInteger(json['balance']) ?? 0,
      commissionBalanceCents:
          Ai68Json.optionalInteger(json['commission_balance']) ?? 0,
      lastLoginAt: Ai68Json.optionalInteger(json['last_login_at']),
      createdAt: Ai68Json.optionalInteger(json['created_at']),
      expiredAt: Ai68Json.optionalInteger(json['expired_at']),
      planId: Ai68Json.optionalInteger(json['plan_id']),
      discount: Ai68Json.optionalDouble(json['discount']),
      commissionRate: Ai68Json.optionalDouble(json['commission_rate']),
      telegramId: Ai68Json.optionalString(json['telegram_id']),
      uuid: Ai68Json.optionalString(json['uuid']),
      avatarUrl: Ai68Json.optionalString(json['avatar_url']),
    );
  }

  final String email;
  final int transferEnableBytes;
  final bool banned;
  final bool remindExpire;
  final bool remindTraffic;
  final int balanceCents;
  final int commissionBalanceCents;
  final int? lastLoginAt;
  final int? createdAt;
  final int? expiredAt;
  final int? planId;
  final double? discount;
  final double? commissionRate;
  final String? telegramId;
  final String? uuid;
  final String? avatarUrl;
}

enum Ai68PlanPeriod {
  month('month_price'),
  quarter('quarter_price'),
  halfYear('half_year_price'),
  year('year_price'),
  twoYears('two_year_price'),
  threeYears('three_year_price'),
  onetime('onetime_price'),
  resetTraffic('reset_price');

  const Ai68PlanPeriod(this.apiValue);

  final String apiValue;
}

final class Ai68Plan {
  const Ai68Plan({
    required this.id,
    required this.name,
    required this.tags,
    required this.pricesCents,
    required this.transferEnableGb,
    required this.show,
    required this.sell,
    required this.renew,
    this.groupId,
    this.content,
    this.capacityLimit,
    this.speedLimitMbps,
    this.deviceLimit,
    this.resetTrafficMethod,
    this.sort,
    this.createdAt,
    this.updatedAt,
  });

  factory Ai68Plan.fromJson(Map<String, dynamic> json) {
    final prices = <Ai68PlanPeriod, int?>{};
    for (final period in Ai68PlanPeriod.values) {
      prices[period] = Ai68Json.optionalInteger(json[period.apiValue]);
    }
    return Ai68Plan(
      id: Ai68Json.integer(json['id'], 'plan.id'),
      name: Ai68Json.string(json['name'], 'plan.name'),
      tags: Ai68Json.strings(json['tags']),
      pricesCents: Map.unmodifiable(prices),
      transferEnableGb: Ai68Json.optionalInteger(json['transfer_enable']) ?? 0,
      show: Ai68Json.boolean(json['show']),
      sell: Ai68Json.boolean(json['sell']),
      renew: Ai68Json.boolean(json['renew']),
      groupId: Ai68Json.optionalInteger(json['group_id']),
      content: Ai68Json.optionalString(json['content']),
      capacityLimit: json['capacity_limit'],
      speedLimitMbps: Ai68Json.optionalDouble(json['speed_limit']),
      deviceLimit: Ai68Json.optionalInteger(json['device_limit']),
      resetTrafficMethod: Ai68Json.optionalInteger(
        json['reset_traffic_method'],
      ),
      sort: Ai68Json.optionalInteger(json['sort']),
      createdAt: Ai68Json.optionalInteger(json['created_at']),
      updatedAt: Ai68Json.optionalInteger(json['updated_at']),
    );
  }

  final int id;
  final String name;
  final List<String> tags;
  final Map<Ai68PlanPeriod, int?> pricesCents;
  final int transferEnableGb;
  final bool show;
  final bool sell;
  final bool renew;
  final int? groupId;
  final String? content;
  final Object? capacityLimit;
  final double? speedLimitMbps;
  final int? deviceLimit;
  final int? resetTrafficMethod;
  final int? sort;
  final int? createdAt;
  final int? updatedAt;
}

final class Ai68Subscription {
  const Ai68Subscription({
    required this.subscriptionToken,
    required this.subscribeUrl,
    required this.uploadBytes,
    required this.downloadBytes,
    required this.transferEnableBytes,
    this.planId,
    this.expiredAt,
    this.email,
    this.uuid,
    this.deviceLimit,
    this.speedLimitMbps,
    this.nextResetAt,
    this.resetDay,
    this.plan,
  });

  factory Ai68Subscription.fromJson(Map<String, dynamic> json) {
    final planJson = json['plan'];
    return Ai68Subscription(
      subscriptionToken: Ai68Json.string(json['token'], 'subscription.token'),
      subscribeUrl: Uri.parse(
        Ai68Json.string(json['subscribe_url'], 'subscription.subscribe_url'),
      ),
      uploadBytes: Ai68Json.optionalInteger(json['u']) ?? 0,
      downloadBytes: Ai68Json.optionalInteger(json['d']) ?? 0,
      transferEnableBytes:
          Ai68Json.optionalInteger(json['transfer_enable']) ?? 0,
      planId: Ai68Json.optionalInteger(json['plan_id']),
      expiredAt: Ai68Json.optionalInteger(json['expired_at']),
      email: Ai68Json.optionalString(json['email']),
      uuid: Ai68Json.optionalString(json['uuid']),
      deviceLimit: Ai68Json.optionalInteger(json['device_limit']),
      speedLimitMbps: Ai68Json.optionalDouble(json['speed_limit']),
      nextResetAt: Ai68Json.optionalInteger(json['next_reset_at']),
      resetDay: Ai68Json.optionalInteger(json['reset_day']),
      plan: planJson == null
          ? null
          : Ai68Plan.fromJson(Ai68Json.object(planJson, 'subscription.plan')),
    );
  }

  final String subscriptionToken;
  final Uri subscribeUrl;
  final int uploadBytes;
  final int downloadBytes;
  final int transferEnableBytes;
  final int? planId;
  final int? expiredAt;
  final String? email;
  final String? uuid;
  final int? deviceLimit;
  final double? speedLimitMbps;
  final int? nextResetAt;
  final int? resetDay;
  final Ai68Plan? plan;

  int get usedBytes => uploadBytes + downloadBytes;
}

enum Ai68OrderStatus {
  pending(0),
  processing(1),
  cancelled(2),
  completed(3),
  discounted(4),
  unknown(-1);

  const Ai68OrderStatus(this.code);

  factory Ai68OrderStatus.fromCode(int code) {
    return Ai68OrderStatus.values.firstWhere(
      (value) => value.code == code,
      orElse: () => Ai68OrderStatus.unknown,
    );
  }

  final int code;
}

final class Ai68Order {
  const Ai68Order({
    required this.id,
    required this.planId,
    required this.period,
    required this.tradeNo,
    required this.totalAmountCents,
    required this.status,
    required this.type,
    this.paymentId,
    this.handlingAmountCents,
    this.balanceAmountCents,
    this.discountAmountCents,
    this.createdAt,
    this.updatedAt,
    this.paidAt,
    this.plan,
  });

  factory Ai68Order.fromJson(Map<String, dynamic> json) {
    final planJson = json['plan'];
    final statusCode = Ai68Json.optionalInteger(json['status']) ?? -1;
    return Ai68Order(
      id: Ai68Json.integer(json['id'], 'order.id'),
      planId: Ai68Json.integer(json['plan_id'], 'order.plan_id'),
      period: Ai68Json.string(json['period'], 'order.period'),
      tradeNo: Ai68Json.string(json['trade_no'], 'order.trade_no'),
      totalAmountCents: Ai68Json.optionalInteger(json['total_amount']) ?? 0,
      status: Ai68OrderStatus.fromCode(statusCode),
      type: Ai68Json.optionalInteger(json['type']) ?? 0,
      paymentId: Ai68Json.optionalInteger(json['payment_id']),
      handlingAmountCents: Ai68Json.optionalInteger(json['handling_amount']),
      balanceAmountCents: Ai68Json.optionalInteger(json['balance_amount']),
      discountAmountCents: Ai68Json.optionalInteger(json['discount_amount']),
      createdAt: Ai68Json.optionalInteger(json['created_at']),
      updatedAt: Ai68Json.optionalInteger(json['updated_at']),
      paidAt: Ai68Json.optionalInteger(json['paid_at']),
      plan: planJson == null
          ? null
          : Ai68Plan.fromJson(Ai68Json.object(planJson, 'order.plan')),
    );
  }

  final int id;
  final int planId;
  final String period;
  final String tradeNo;
  final int totalAmountCents;
  final Ai68OrderStatus status;
  final int type;
  final int? paymentId;
  final int? handlingAmountCents;
  final int? balanceAmountCents;
  final int? discountAmountCents;
  final int? createdAt;
  final int? updatedAt;
  final int? paidAt;
  final Ai68Plan? plan;
}

final class Ai68PaymentMethod {
  const Ai68PaymentMethod({
    required this.id,
    required this.name,
    required this.payment,
    required this.handlingFeeFixedCents,
    required this.handlingFeePercent,
    this.iconUrl,
  });

  factory Ai68PaymentMethod.fromJson(Map<String, dynamic> json) {
    return Ai68PaymentMethod(
      id: Ai68Json.integer(json['id'], 'payment.id'),
      name: Ai68Json.string(json['name'], 'payment.name'),
      payment: Ai68Json.string(json['payment'], 'payment.payment'),
      handlingFeeFixedCents:
          Ai68Json.optionalInteger(json['handling_fee_fixed']) ?? 0,
      handlingFeePercent:
          Ai68Json.optionalDouble(json['handling_fee_percent']) ?? 0,
      iconUrl: Ai68Json.optionalString(json['icon']),
    );
  }

  final int id;
  final String name;
  final String payment;
  final int handlingFeeFixedCents;
  final double handlingFeePercent;
  final String? iconUrl;
}

final class Ai68CheckoutResult {
  const Ai68CheckoutResult({required this.type, required this.data});

  factory Ai68CheckoutResult.fromJson(Map<String, dynamic> json) {
    return Ai68CheckoutResult(
      type: Ai68Json.integer(json['type'], 'checkout.type'),
      data: json['data'],
    );
  }

  final int type;
  final Object? data;

  Uri? get redirectUrl {
    if (type != 1 || data is! String) return null;
    return Uri.tryParse(data! as String);
  }
}

final class Ai68NoticePage {
  const Ai68NoticePage({required this.items, required this.total});

  final List<Ai68Notice> items;
  final int total;
}

final class Ai68Notice {
  const Ai68Notice({
    required this.id,
    required this.title,
    required this.content,
    required this.tags,
    required this.show,
    this.imageUrl,
    this.sort,
    this.createdAt,
    this.updatedAt,
  });

  factory Ai68Notice.fromJson(Map<String, dynamic> json) {
    return Ai68Notice(
      id: Ai68Json.integer(json['id'], 'notice.id'),
      title: Ai68Json.string(json['title'], 'notice.title'),
      content: Ai68Json.optionalString(json['content']) ?? '',
      tags: Ai68Json.strings(json['tags']),
      show: Ai68Json.boolean(json['show']),
      imageUrl: Ai68Json.optionalString(json['img_url']),
      sort: Ai68Json.optionalInteger(json['sort']),
      createdAt: Ai68Json.optionalInteger(json['created_at']),
      updatedAt: Ai68Json.optionalInteger(json['updated_at']),
    );
  }

  final int id;
  final String title;
  final String content;
  final List<String> tags;
  final bool show;
  final String? imageUrl;
  final int? sort;
  final int? createdAt;
  final int? updatedAt;
}

final class Ai68Server {
  const Ai68Server({
    required this.id,
    required this.type,
    required this.name,
    required this.rate,
    required this.tags,
    required this.isOnline,
    required this.cacheKey,
    this.version,
    this.lastCheckAt,
  });

  factory Ai68Server.fromJson(Map<String, dynamic> json) {
    return Ai68Server(
      id: Ai68Json.integer(json['id'], 'server.id'),
      type: Ai68Json.string(json['type'], 'server.type'),
      name: Ai68Json.string(json['name'], 'server.name'),
      rate: Ai68Json.optionalDouble(json['rate']) ?? 1,
      tags: Ai68Json.strings(json['tags']),
      isOnline: Ai68Json.boolean(json['is_online']),
      cacheKey: Ai68Json.optionalString(json['cache_key']) ?? '',
      version: Ai68Json.optionalString(json['version']),
      lastCheckAt: Ai68Json.optionalInteger(json['last_check_at']),
    );
  }

  final int id;
  final String type;
  final String name;
  final double rate;
  final List<String> tags;
  final bool isOnline;
  final String cacheKey;
  final String? version;
  final int? lastCheckAt;
}

final class Ai68TrafficLog {
  const Ai68TrafficLog({
    required this.downloadBytes,
    required this.uploadBytes,
    required this.recordedAt,
    required this.serverRate,
  });

  factory Ai68TrafficLog.fromJson(Map<String, dynamic> json) {
    return Ai68TrafficLog(
      downloadBytes: Ai68Json.optionalInteger(json['d']) ?? 0,
      uploadBytes: Ai68Json.optionalInteger(json['u']) ?? 0,
      recordedAt: Ai68Json.integer(json['record_at'], 'traffic.record_at'),
      serverRate: Ai68Json.optionalDouble(json['server_rate']) ?? 1,
    );
  }

  final int downloadBytes;
  final int uploadBytes;
  final int recordedAt;
  final double serverRate;
}
