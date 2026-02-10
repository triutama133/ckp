import 'dart:math';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';

/// GroupService abstracts group membership and invite operations.
/// It supports local DB, VPS (HTTP) and Supabase providers and can be
/// switched at runtime via `useRemote` + `provider`.
class GroupService {
  GroupService._private();
  static final GroupService instance = GroupService._private();

  /// When true, attempt remote operations according to `provider`.
  bool useRemote = false;

  /// Either 'vps' or 'supabase'. Defaults to 'vps'.
  String provider = 'vps';

  /// VPS base URL (used when provider == 'vps').
  String? remoteBaseUrl;

  final _rng = Random();
  Map<String, String> get _jsonHeaders => {'content-type': 'application/json'};

  Future<void> inviteByEmail(
    String groupId,
    String createdBy,
    String email, {
    String? groupName,
  }) async {
    if (!useRemote || provider != 'supabase') {
      throw Exception('Invite via email hanya tersedia untuk Supabase');
    }

    final client = Supabase.instance.client;
    final normEmail = email.trim().toLowerCase();
    if (normEmail.isEmpty) {
      throw Exception('Email tidak boleh kosong');
    }

    final user = await client
        .from('users')
        .select('id,email,full_name')
        .eq('email', normEmail)
        .maybeSingle();

    if (user == null) {
      throw Exception('Email belum terdaftar');
    }

    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) {
      throw Exception('User tidak ditemukan');
    }
    if (userId == createdBy) {
      throw Exception('Tidak bisa mengundang diri sendiri');
    }

    final now = DateTime.now().toIso8601String();
    final existing = await client
        .from('group_members')
        .select('id,status')
        .eq('group_id', groupId)
        .eq('user_id', userId)
        .maybeSingle();

    String memberId;
    if (existing != null) {
      memberId = existing['id']?.toString() ?? 'gm_${groupId}_$userId';
      final status = existing['status']?.toString();
      if (status == 'accepted') {
        throw Exception('User sudah menjadi anggota');
      }
      await client.from('group_members').update({
        'status': 'invited',
        'role': 'member',
        'joined_at': null,
        'updated_at': now,
      }).eq('id', memberId);
    } else {
      memberId = 'gm_${groupId}_$userId';
      await client.from('group_members').insert({
        'id': memberId,
        'group_id': groupId,
        'user_id': userId,
        'role': 'member',
        'status': 'invited',
        'joined_at': null,
        'created_at': now,
        'updated_at': now,
      });
    }

    String? resolvedGroupName = groupName;
    if (resolvedGroupName == null || resolvedGroupName.isEmpty) {
      final g = await client.from('groups').select('name').eq('id', groupId).maybeSingle();
      resolvedGroupName = g?['name']?.toString() ?? 'Grup';
    }

    await client.from('notifications').insert({
      'id': 'notif_${DateTime.now().millisecondsSinceEpoch}_${_rng.nextInt(999999)}',
      'user_id': userId,
      'title': 'Undangan Grup',
      'body': 'Anda diundang ke grup "$resolvedGroupName"',
      'type': 'group_invite',
      'data': {
        'group_id': groupId,
        'member_id': memberId,
        'inviter_id': createdBy,
        'group_name': resolvedGroupName,
      },
      'is_read': false,
      'created_at': now,
    });
  }

  Future<void> respondToInvite(String memberId, {required bool accept}) async {
    if (!useRemote || provider != 'supabase') {
      throw Exception('Respons invite hanya tersedia untuk Supabase');
    }

    final client = Supabase.instance.client;
    final now = DateTime.now().toIso8601String();

    if (accept) {
      await client.from('group_members').update({
        'status': 'accepted',
        'joined_at': now,
        'updated_at': now,
      }).eq('id', memberId);
    } else {
      await client.from('group_members').delete().eq('id', memberId);
    }
  }

  // ============ MEMBERSHIP (list/promote/remove) ============
  Future<List<GroupMember>> getMembers(String groupId) async {
    if (useRemote && provider == 'supabase') {
      try {
        final client = Supabase.instance.client;
        final data = await client
            .from('group_members')
            .select('*, users!inner(email)')
            .eq('groupId', groupId)
            .order('joinedAt', ascending: false);
        
        final rows = (data as List).cast<Map<String, dynamic>>();
        return rows.map((m) {
          final userEmail = m['users'] != null && m['users'] is Map 
              ? m['users']['email'] as String?
              : null;
          return GroupMember.fromMap({
            ...m,
            'email': userEmail,
          });
        }).toList();
      } catch (e) {
        throw Exception('Gagal mengambil anggota grup: $e');
      }
    }
    // For VPS remote we currently fall back to local DB (or implement HTTP list if desired)
    return DBService.instance.getGroupMembers(groupId);
  }

  Future<void> promoteMember(String memberId, String role) async {
    if (useRemote && provider == 'supabase') {
      try {
        final client = Supabase.instance.client;
        await client
            .from('group_members')
            .update({'role': role})
            .eq('id', memberId);
        return;
      } catch (e) {
        throw Exception('Gagal promote member: $e');
      }
    }
    await DBService.instance.updateGroupMemberRole(memberId, role);
  }

  Future<void> removeMember(String memberId) async {
    if (useRemote && provider == 'supabase') {
      try {
        final client = Supabase.instance.client;
        await client
            .from('group_members')
            .delete()
            .eq('id', memberId);
        return;
      } catch (e) {
        throw Exception('Gagal menghapus member: $e');
      }
    }
    await DBService.instance.removeGroupMember(memberId);
  }

  // ============ INVITES ============
  Future<GroupInvite> generateInvite(String groupId, String createdBy, {Duration? ttl}) async {
    final id = 'inv_${DateTime.now().millisecondsSinceEpoch}_${_rng.nextInt(999999)}';
    final token = 't_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rng.nextInt(9999)}';
    final now = DateTime.now();
    final expires = ttl != null ? now.add(ttl) : now.add(const Duration(days: 7));

    if (useRemote) {
      if (provider == 'supabase') {
        try {
          final client = Supabase.instance.client;
          final data = await client.from('group_invites').insert({
            'id': id,
            'groupId': groupId,
            'token': token,
            'createdBy': createdBy,
            'createdAt': now.toIso8601String(),
            'expiresAt': expires.toIso8601String(),
          }).select().single();
          
          return GroupInvite.fromMap({
            'id': data['id'],
            'groupId': data['groupId'],
            'token': data['token'],
            'createdBy': data['createdBy'],
            'createdAt': DateTime.parse(data['createdAt']).millisecondsSinceEpoch,
            'expiresAt': data['expiresAt'] != null ? DateTime.parse(data['expiresAt']).millisecondsSinceEpoch : null,
            'usedAt': data['usedAt'] != null ? DateTime.parse(data['usedAt']).millisecondsSinceEpoch : null,
          });
        } catch (e) {
          throw Exception('Gagal membuat invite: $e');
        }
      }
      // provider == 'vps'
      return await createInviteRemote(groupId, createdBy, ttl: ttl);
    }

    final invite = GroupInvite(id: id, groupId: groupId, token: token, createdBy: createdBy, createdAt: now, expiresAt: expires, usedAt: null);
    await DBService.instance.insertGroupInvite(invite);
    return invite;
  }

  Future<void> revokeInvite(String inviteId) async {
    if (useRemote) {
      if (provider == 'supabase') {
        try {
          final client = Supabase.instance.client;
          await client
              .from('group_invites')
              .delete()
              .eq('id', inviteId);
          return;
        } catch (e) {
          throw Exception('Gagal revoke invite: $e');
        }
      }
      // vps
      if (remoteBaseUrl == null) throw Exception('remoteBaseUrl not configured');
      final url = Uri.parse('$remoteBaseUrl/groups/invites/$inviteId/revoke');
      final res = await http.post(url, headers: _jsonHeaders);
      if (res.statusCode >= 400) throw Exception('remote revoke failed: $res');
      return;
    }
    await DBService.instance.deleteInvite(inviteId);
  }

  Future<GroupInvite> createInviteRemote(String groupId, String createdBy, {Duration? ttl}) async {
    if (remoteBaseUrl == null) throw Exception('remoteBaseUrl not configured');
    final url = Uri.parse('$remoteBaseUrl/groups/$groupId/invites');
    final body = jsonEncode({'createdBy': createdBy, 'ttlSeconds': ttl?.inSeconds});
    final res = await http.post(url, headers: _jsonHeaders, body: body);
    if (res.statusCode != 200) throw Exception('createInviteRemote failed');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return GroupInvite.fromMap({
      'id': data['id'],
      'groupId': data['groupId'],
      'token': data['token'],
      'createdBy': data['createdBy'],
      'createdAt': DateTime.parse(data['createdAt']).millisecondsSinceEpoch,
      'expiresAt': data['expiresAt'] != null ? DateTime.parse(data['expiresAt']).millisecondsSinceEpoch : null,
      'usedAt': data['usedAt'] != null ? DateTime.parse(data['usedAt']).millisecondsSinceEpoch : null,
    });
  }

  Future<GroupMember?> acceptInviteRemote(String token, String userId) async {
    if (useRemote && provider == 'supabase') {
      try {
        final client = Supabase.instance.client;
        final invData = await client
            .from('group_invites')
            .select()
            .eq('token', token)
            .single();
        
        if (invData['usedAt'] != null) return null;
        if (invData['expiresAt'] != null && 
            DateTime.parse(invData['expiresAt']).isBefore(DateTime.now())) return null;
        
        final memberId = 'gm_${invData['groupId']}_${userId}_${DateTime.now().millisecondsSinceEpoch}';
        final joinedAt = DateTime.now().toIso8601String();
        
        final memberData = await client.from('group_members').insert({
          'id': memberId,
          'groupId': invData['groupId'],
          'userId': userId,
          'role': 'member',
          'status': 'accepted',
          'joinedAt': joinedAt,
        }).select().single();
        
        await client
            .from('group_invites')
            .update({'usedAt': DateTime.now().toIso8601String()})
            .eq('id', invData['id']);
        
        return GroupMember.fromMap({
          'id': memberData['id'],
          'groupId': memberData['groupId'],
          'userId': memberData['userId'],
          'role': memberData['role'],
          'status': memberData['status'],
          'joinedAt': memberData['joinedAt'] != null 
              ? DateTime.parse(memberData['joinedAt']).millisecondsSinceEpoch 
              : null,
        });
      } catch (e) {
        return null;
      }
    }

    // VPS path
    if (remoteBaseUrl == null) throw Exception('remoteBaseUrl not configured');
    final url = Uri.parse('$remoteBaseUrl/invites/accept');
    final body = jsonEncode({'token': token, 'userId': userId});
    final res = await http.post(url, headers: _jsonHeaders, body: body);
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return GroupMember.fromMap({
      'id': data['id'],
      'groupId': data['groupId'],
      'userId': data['userId'],
      'role': data['role'],
      'status': data['status'],
      'joinedAt': data['joinedAt'] != null ? DateTime.parse(data['joinedAt']).millisecondsSinceEpoch : null,
    });
  }

  /// Accept invite (public): delegates to remote or local depending on config.
  Future<GroupMember?> acceptInvite(String token, String userId) async {
    if (useRemote) {
      return await acceptInviteRemote(token, userId);
    }
    final inv = await DBService.instance.getInviteByToken(token);
    if (inv == null) return null;
    final now = DateTime.now();
    if (inv.expiresAt != null && inv.expiresAt!.isBefore(now)) return null;
    
    final memberId = 'gm_${inv.groupId}_${userId}_${now.millisecondsSinceEpoch}';
    final member = GroupMember(
      id: memberId,
      groupId: inv.groupId,
      userId: userId,
      role: 'member',
      status: 'accepted',
      joinedAt: now,
    );
    
    await DBService.instance.insertGroupMember(member);
    await DBService.instance.markInviteUsed(inv.id);
    return member;
  }
}
