import 'package:flutter/material.dart';

/// Maps the `icon` string from the CMS menu (a Material/Bootstrap-ish icon
/// name) to a Flutter [IconData].
///
/// The CMS stores free-form icon names, so this is a best-effort lookup with a
/// sensible default. Add entries as the admin's icon picker grows. Unknown
/// names fall back to [defaultIcon] rather than throwing.
IconData iconFromName(String? name, {IconData fallback = defaultIcon}) {
  if (name == null || name.trim().isEmpty) return fallback;
  final key = name.trim().toLowerCase().replaceAll('-', '_');
  return _icons[key] ?? fallback;
}

const IconData defaultIcon = Icons.chevron_right;

const Map<String, IconData> _icons = {
  'home': Icons.home,
  'house': Icons.home,
  'newspaper': Icons.newspaper,
  'news': Icons.newspaper,
  'article': Icons.article,
  'book': Icons.menu_book,
  'menu_book': Icons.menu_book,
  'publications': Icons.menu_book,
  'library': Icons.local_library,
  'file': Icons.insert_drive_file,
  'pdf': Icons.picture_as_pdf,
  'description': Icons.description,
  'services': Icons.design_services,
  'design_services': Icons.design_services,
  'briefcase': Icons.work,
  'work': Icons.work,
  'contact': Icons.contact_mail,
  'contact_mail': Icons.contact_mail,
  'mail': Icons.mail,
  'email': Icons.email,
  'envelope': Icons.email,
  'phone': Icons.phone,
  'call': Icons.call,
  'location': Icons.location_on,
  'map': Icons.map,
  'geo_alt': Icons.location_on,
  'info': Icons.info,
  'info_circle': Icons.info,
  'about': Icons.info_outline,
  'search': Icons.search,
  'gallery': Icons.photo_library,
  'images': Icons.photo_library,
  'photo': Icons.photo,
  'image': Icons.image,
  'video': Icons.ondemand_video,
  'play': Icons.play_circle,
  'calendar': Icons.calendar_today,
  'event': Icons.event,
  'megaphone': Icons.campaign,
  'campaign': Icons.campaign,
  'announcement': Icons.campaign,
  'bullhorn': Icons.campaign,
  'speech': Icons.record_voice_over,
  'mic': Icons.mic,
  'blog': Icons.rss_feed,
  'rss': Icons.rss_feed,
  'faq': Icons.help_outline,
  'help': Icons.help_outline,
  'question': Icons.help_outline,
  'question_circle': Icons.help_outline,
  'people': Icons.people,
  'users': Icons.people,
  'person': Icons.person,
  'building': Icons.apartment,
  'company': Icons.apartment,
  'companies': Icons.business,
  'business': Icons.business,
  'bank': Icons.account_balance,
  'chart': Icons.show_chart,
  'bar_chart': Icons.bar_chart,
  'graph_up': Icons.show_chart,
  'investment': Icons.trending_up,
  'trending_up': Icons.trending_up,
  'money': Icons.attach_money,
  'star': Icons.star,
  'globe': Icons.public,
  'public': Icons.public,
  'link': Icons.link,
  'external': Icons.open_in_new,
  'settings': Icons.settings,
  'gear': Icons.settings,
  'notifications': Icons.notifications,
  'bell': Icons.notifications,
  'list': Icons.list,
  'grid': Icons.grid_view,
  'dashboard': Icons.dashboard,
};
