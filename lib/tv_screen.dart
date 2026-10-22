import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'core.dart';
import 'widgets.dart';

class TVLayoutScreen extends StatefulWidget {
  final int activeSection; // 0: TV ao Vivo, 1: Filmes, 2: Séries, 3: Favoritos, 4: Histórico
  final ValueChanged<int> onSectionChanged;
  final String selectedCategory;
  final List<String> categories;
  final ValueChanged<String> onCategorySelected;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final List<StreamItem> filteredItems;
  final List<SeriesGroup> groupedSeries;
  final StreamItem? selectedLiveChannel;
  final ValueChanged<StreamItem> onLiveChannelSelected;
  final void Function(StreamItem item, List<StreamItem> playlist) onOpenFullScreen;
  final ValueChanged<StreamItem> onOpenMovieDetails;
  final ValueChanged<SeriesGroup> onOpenSeriesDetails;
  final Set<String> favorites;
  final ValueChanged<String> onToggleFavorite;
  final Map<String, double> watchProgress;
  final bool isAdultUnlocked;
  final Future<bool> Function() onUnlockAdult;
  final VoidCallback onRefreshPlaylist;
  final VoidCallback onSwitchAccount;

  const TVLayoutScreen({
    super.key,
    required this.activeSection,
    required this.onSectionChanged,
    required this.selectedCategory,
    required this.categories,
    required this.onCategorySelected,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.filteredItems,
    required this.groupedSeries,
    required this.selectedLiveChannel,
    required this.onLiveChannelSelected,
    required this.onOpenFullScreen,
    required this.onOpenMovieDetails,
    required this.onOpenSeriesDetails,
    required this.favorites,
    required this.onToggleFavorite,
    required this.watchProgress,
    required this.isAdultUnlocked,
    required this.onUnlockAdult,
    required this.onRefreshPlaylist,
    required this.onSwitchAccount,
  });

  @override
  State<TVLayoutScreen> createState() => _TVLayoutScreenState();
}

class _TVLayoutScreenState extends State<TVLayoutScreen> {
  final SharedStreamEngine _engine = SharedStreamEngine.instance;

  // Nós de foco para as 5 seções principais do Menu Lateral
  late final List<FocusNode> _navFocusNodes;

  // Nós de foco estratégicos para navegação por controle remoto
  final FocusNode _firstLiveCatFocusNode = FocusNode();
  final FocusNode _firstVodCatFocusNode = FocusNode();
  final FocusNode _vodSearchFocusNode = FocusNode();
  final FocusNode _liveSearchFocusNode = FocusNode();
  final FocusNode _firstCatalogItemFocusNode = FocusNode();
  final FocusNode _firstLiveChannelFocusNode = FocusNode();
  final FocusNode _previewFullScreenBtnNode = FocusNode();

  // Controladores de rolagem para categorias e listas
  final ScrollController _liveCategoryScrollController = ScrollController();
  final ScrollController _vodCategoryScrollController = ScrollController();
  final ScrollController _channelListScrollController = ScrollController();
  final ScrollController _catalogCarouselScrollController = ScrollController();

  // Flag para mover o foco automaticamente ao 1º item após selecionar uma categoria
  bool _pendingFocusFirstCatalogItem = false;

  @override
  void initState() {
    super.initState();
    _navFocusNodes = List.generate(5, (_) => FocusNode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyInitialSectionFocus();
    });
  }

  @override
  void didUpdateWidget(covariant TVLayoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.activeSection != widget.activeSection) {
      _pendingFocusFirstCatalogItem = false;
      _resetScrollPositions();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyInitialSectionFocus();
      });
      return;
    }

    if (oldWidget.selectedCategory != widget.selectedCategory) {
      if (_catalogCarouselScrollController.hasClients) {
        _catalogCarouselScrollController.jumpTo(0);
      }
      if (_channelListScrollController.hasClients) {
        _channelListScrollController.jumpTo(0);
      }
    }

    if (_pendingFocusFirstCatalogItem) {
      _pendingFocusFirstCatalogItem = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusFirstItemOfSelectedCategory();
      });
    }
  }

  @override
  void dispose() {
    for (final node in _navFocusNodes) {
      node.dispose();
    }
    _firstLiveCatFocusNode.dispose();
    _firstVodCatFocusNode.dispose();
    _vodSearchFocusNode.dispose();
    _liveSearchFocusNode.dispose();
    _firstCatalogItemFocusNode.dispose();
    _firstLiveChannelFocusNode.dispose();
    _previewFullScreenBtnNode.dispose();

    _liveCategoryScrollController.dispose();
    _vodCategoryScrollController.dispose();
    _channelListScrollController.dispose();
    _catalogCarouselScrollController.dispose();
    super.dispose();
  }

  void _resetScrollPositions() {
    if (_liveCategoryScrollController.hasClients) {
      _liveCategoryScrollController.jumpTo(0);
    }
    if (_vodCategoryScrollController.hasClients) {
      _vodCategoryScrollController.jumpTo(0);
    }
    if (_channelListScrollController.hasClients) {
      _channelListScrollController.jumpTo(0);
    }
    if (_catalogCarouselScrollController.hasClients) {
      _catalogCarouselScrollController.jumpTo(0);
    }
  }

  /// Regras de Foco ao entrar em cada seção:
  /// - TV ao Vivo (0): Foco na primeira categoria ("Todas").
  /// - Filmes (1) e Séries (2): Foco na barra de pesquisa ("Pesquisar").
  /// - Favoritos (3): Foco na primeira subcategoria ("Canais").
  /// - Histórico (4): Foco no primeiro item ou no menu.
  void _applyInitialSectionFocus() {
    if (!mounted) return;
    if (widget.activeSection == 0) {
      if (_firstLiveCatFocusNode.canRequestFocus) {
        _firstLiveCatFocusNode.requestFocus();
      }
    } else if (widget.activeSection == 1 || widget.activeSection == 2) {
      if (_vodSearchFocusNode.canRequestFocus) {
        _vodSearchFocusNode.requestFocus();
      }
    } else if (widget.activeSection == 3) {
      if (_firstVodCatFocusNode.canRequestFocus) {
        _firstVodCatFocusNode.requestFocus();
      }
    } else if (widget.activeSection == 4) {
      if (widget.filteredItems.isNotEmpty && _firstCatalogItemFocusNode.canRequestFocus) {
        _firstCatalogItemFocusNode.requestFocus();
      } else if (_vodSearchFocusNode.canRequestFocus) {
        _vodSearchFocusNode.requestFocus();
      }
    }
  }

  /// Move o foco automaticamente para o primeiro filme, série ou canal
  /// quando o usuário seleciona uma categoria.
  void _focusFirstItemOfSelectedCategory() {
    if (!mounted) return;

    if (_isFavoritesLiveSubcategory) {
      if (widget.filteredItems.isNotEmpty && _firstLiveChannelFocusNode.canRequestFocus) {
        _firstLiveChannelFocusNode.requestFocus();
      }
      return;
    }

    final hasCatalogItems = _isDisplayingSeries
        ? widget.groupedSeries.isNotEmpty
        : widget.filteredItems.isNotEmpty;

    if (hasCatalogItems && _firstCatalogItemFocusNode.canRequestFocus) {
      _firstCatalogItemFocusNode.requestFocus();
    }
  }

  void _focusActiveSidebarItem() {
    final idx = widget.activeSection.clamp(0, _navFocusNodes.length - 1);
    if (_navFocusNodes[idx].canRequestFocus) {
      _navFocusNodes[idx].requestFocus();
    }
  }

  bool get _isSidebarFocused => _navFocusNodes.any((n) => n.hasFocus);

  bool get _isFavoritesLiveSubcategory =>
      widget.activeSection == 3 &&
      (widget.selectedCategory == 'Canais' || widget.selectedCategory == 'TV ao Vivo');

  bool get _isFavoritesSeriesSubcategory =>
      widget.activeSection == 3 && widget.selectedCategory == 'Séries';

  bool get _isDisplayingSeries =>
      widget.activeSection == 2 || _isFavoritesSeriesSubcategory;

  bool _isSeriesFavorited(SeriesGroup series) {
    if (widget.favorites.contains('series:${series.title}')) return true;
    for (final epList in series.seasons.values) {
      for (final ep in epList) {
        if (widget.favorites.contains(ep.id)) return true;
      }
    }
    return false;
  }

  void _handleToggleSeriesFavorite(SeriesGroup series) {
    final allEps = series.seasons.values.expand((e) => e).toList();
    final favEps = allEps.where((ep) => widget.favorites.contains(ep.id)).toList();
    final hasSyntheticKey = widget.favorites.contains('series:${series.title}');

    if (favEps.isNotEmpty || hasSyntheticKey) {
      for (final ep in favEps) {
        widget.onToggleFavorite(ep.id);
      }
      if (hasSyntheticKey) {
        widget.onToggleFavorite('series:${series.title}');
      }
      showQuickFavoriteToast(
        context,
        title: series.title,
        isAdded: false,
      );
    } else if (allEps.isNotEmpty) {
      widget.onToggleFavorite(allEps.first.id);
      showQuickFavoriteToast(
        context,
        title: series.title,
        isAdded: true,
      );
    }
  }

  void _handleToggleItemFavorite(StreamItem item) {
    final isCurrentlyFav = widget.favorites.contains(item.id);
    widget.onToggleFavorite(item.id);
    showQuickFavoriteToast(
      context,
      title: item.name,
      isAdded: !isCurrentlyFav,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (!_isSidebarFocused) {
          _focusActiveSidebarItem();
          return;
        }
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF111520),
            title: const Text('Sair do aplicativo?',
                style: TextStyle(color: Colors.white, fontSize: 18)),
            content: const Text('Deseja realmente fechar o UNEX PLAY?',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Não', style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  SystemNavigator.pop();
                },
                child: const Text('Sim, sair', style: TextStyle(color: Color(0xFF00E5FF))),
              ),
            ],
          ),
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF07090E),
        body: Row(
          children: [
            _buildLeftNavigationRail(),
            Expanded(
              child: widget.activeSection == 0
                  ? _buildLiveTVSection()
                  : _buildCatalogAndFavoritesSection(),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // MENU LATERAL ESQUERDO (COM TESTE DE VELOCIDADE INTEGRADO)
  // ===========================================================================
  Widget _buildLeftNavigationRail() {
    final navItems = [
      {'icon': Icons.live_tv_rounded, 'label': 'TV ao Vivo', 'index': 0},
      {'icon': Icons.movie_creation_rounded, 'label': 'Filmes', 'index': 1},
      {'icon': Icons.video_library_rounded, 'label': 'Séries', 'index': 2},
      {'icon': Icons.star_rounded, 'label': 'Favoritos', 'index': 3},
      {'icon': Icons.history_rounded, 'label': 'Histórico', 'index': 4},
    ];

    return Container(
      width: 106,
      decoration: BoxDecoration(
        color: const Color(0xFF0C0F17),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.06), width: 1),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Logo UNEX
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF0088FF)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'UNEX',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Seções Principais e Ações Inferiores ajustáveis sem overflow
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight - 8),
                      child: IntrinsicHeight(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 5 Abas Principais
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: navItems.map((item) {
                                final int idx = item['index'] as int;
                                final bool isSelected = widget.activeSection == idx;
                                return TVFocusableItem(
                                  focusNode: _navFocusNodes[idx],
                                  autoScroll: false,
                                  onMoveRight: _applyInitialSectionFocus,
                                  onSelect: () {
                                    if (widget.activeSection != idx) {
                                      widget.onSectionChanged(idx);
                                    } else {
                                      _applyInitialSectionFocus();
                                    }
                                  },
                                  builder: (context, isFocused) => AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 86,
                                    margin: const EdgeInsets.symmetric(vertical: 3.5),
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: isFocused
                                          ? const Color(0xFF00E5FF)
                                          : isSelected
                                              ? const Color(0xFF00E5FF).withOpacity(0.14)
                                              : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isFocused
                                            ? Colors.white
                                            : isSelected
                                                ? const Color(0xFF00E5FF).withOpacity(0.45)
                                                : Colors.transparent,
                                        width: isFocused ? 1.8 : 1.0,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          item['icon'] as IconData,
                                          size: 20,
                                          color: isFocused
                                              ? Colors.black
                                              : isSelected
                                                  ? const Color(0xFF00E5FF)
                                                  : Colors.white60,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          item['label'] as String,
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: isFocused || isSelected
                                                ? FontWeight.w800
                                                : FontWeight.w500,
                                            color: isFocused
                                                ? Colors.black
                                                : isSelected
                                                    ? Colors.white
                                                    : Colors.white60,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),

                            // Utilitários Inferiores (Inclui Teste de Velocidade)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Divider(
                                  color: Colors.white.withOpacity(0.08),
                                  indent: 18,
                                  endIndent: 18,
                                  height: 12,
                                ),
                                _buildSidebarUtilityButton(
                                  icon: Icons.speed_rounded,
                                  label: 'Velocidade',
                                  accentColor: const Color(0xFF00E5FF),
                                  onTap: () => showSpeedTestDialog(
                                    context,
                                    deviceMode: DeviceMode.tv,
                                  ),
                                ),
                                _buildSidebarUtilityButton(
                                  icon: Icons.shield_outlined,
                                  label: 'Controle +18',
                                  onTap: () => showParentalControlSettingsDialog(
                                    context,
                                    deviceMode: DeviceMode.tv,
                                  ),
                                ),
                                _buildSidebarUtilityButton(
                                  icon: Icons.refresh_rounded,
                                  label: 'Atualizar',
                                  onTap: widget.onRefreshPlaylist,
                                ),
                                _buildSidebarUtilityButton(
                                  icon: Icons.logout_rounded,
                                  label: 'Trocar Lista',
                                  onTap: widget.onSwitchAccount,
                                ),
                                const SizedBox(height: 6),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarUtilityButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? accentColor,
  }) {
    return TVFocusableItem(
      autoScroll: false,
      onMoveRight: _applyInitialSectionFocus,
      onSelect: onTap,
      builder: (context, isFocused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 86,
        margin: const EdgeInsets.symmetric(vertical: 2.5),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color: isFocused ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFocused ? Colors.white : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isFocused ? Colors.black : (accentColor ?? Colors.white54),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: isFocused ? FontWeight.w800 : FontWeight.w500,
                color: isFocused ? Colors.black : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SEÇÃO 0: TV AO VIVO (CATEGORIAS NO TOPO + LISTA DE CANAIS + PRÉVIA FLUIDA)
  // ===========================================================================
  Widget _buildLiveTVSection() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Topo: Título + Dica de Favoritos + Busca + Barra Horizontal de Categorias
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
            child: Row(
              children: [
                const Icon(Icons.live_tv_rounded, color: Color(0xFF00E5FF), size: 24),
                const SizedBox(width: 10),
                const Text(
                  'TV ao Vivo',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                      SizedBox(width: 5),
                      Text(
                        'Segure OK para Favoritar',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _buildSearchButton(
                  focusNode: _liveSearchFocusNode,
                  title: 'Pesquisar Canal ao Vivo',
                  onMoveDown: () {
                    if (_firstLiveCatFocusNode.canRequestFocus) {
                      _firstLiveCatFocusNode.requestFocus();
                    }
                  },
                ),
              ],
            ),
          ),

          // Barra de Categorias da TV ao Vivo
          SizedBox(
            height: 44,
            child: ListView.builder(
              controller: _liveCategoryScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              itemCount: widget.categories.length,
              itemBuilder: (context, idx) {
                final cat = widget.categories[idx];
                final isSelected = cat == widget.selectedCategory;
                return TVFocusableItem(
                  focusNode: idx == 0 ? _firstLiveCatFocusNode : null,
                  onMoveLeft: idx == 0 ? _focusActiveSidebarItem : null,
                  onMoveUp: () {
                    if (_liveSearchFocusNode.canRequestFocus) {
                      _liveSearchFocusNode.requestFocus();
                    }
                  },
                  onMoveDown: () {
                    if (_firstLiveChannelFocusNode.canRequestFocus) {
                      _firstLiveChannelFocusNode.requestFocus();
                    }
                  },
                  onSelect: () => widget.onCategorySelected(cat),
                  builder: (context, isFocused) => _buildCategoryPill(
                    label: cat,
                    isSelected: isSelected,
                    isFocused: isFocused,
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // Área Principal: Lista de Canais (Esquerda) + Painel de Pré-visualização (Direita)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
              child: _buildLiveChannelsAndPreviewBody(),
            ),
          ),
        ],
      ),
    );
  }

  /// Corpo compartilhado entre TV ao Vivo e a subcategoria "Canais" de Favoritos
  Widget _buildLiveChannelsAndPreviewBody() {
    if (widget.filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.activeSection == 3 ? Icons.star_border_rounded : Icons.tv_off_rounded,
              size: 52,
              color: Colors.white24,
            ),
            const SizedBox(height: 12),
            Text(
              widget.activeSection == 3
                  ? 'Nenhum canal favorito adicionado ainda.\nNa TV ao Vivo, segure o botão OK sobre um canal para favoritar!'
                  : 'Nenhum canal encontrado nesta categoria.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13.5, height: 1.4),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        // Coluna Esquerda: Lista de Canais (com fonte 13.5 e suporte a segurar OK para favoritar)
        Expanded(
          flex: 46,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0E121B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: ListView.builder(
              controller: _channelListScrollController,
              padding: const EdgeInsets.all(10),
              itemCount: widget.filteredItems.length,
              itemBuilder: (context, idx) {
                final channel = widget.filteredItems[idx];
                final isSelected = widget.selectedLiveChannel?.id == channel.id;
                final isFav = widget.favorites.contains(channel.id);
                final isLocked = channel.isAdult && !widget.isAdultUnlocked;

                return TVFocusableItem(
                  focusNode: idx == 0 ? _firstLiveChannelFocusNode : null,
                  onMoveLeft: _focusActiveSidebarItem,
                  onMoveRight: () {
                    if (_previewFullScreenBtnNode.canRequestFocus) {
                      _previewFullScreenBtnNode.requestFocus();
                    }
                  },
                  onMoveUp: idx == 0
                      ? () {
                          if (widget.activeSection == 0 &&
                              _firstLiveCatFocusNode.canRequestFocus) {
                            _firstLiveCatFocusNode.requestFocus();
                          } else if (widget.activeSection == 3 &&
                              _firstVodCatFocusNode.canRequestFocus) {
                            _firstVodCatFocusNode.requestFocus();
                          }
                        }
                      : null,
                  onSelect: () async {
                    if (isLocked) {
                      final ok = await widget.onUnlockAdult();
                      if (!ok) return;
                    }
                    if (isSelected) {
                      widget.onOpenFullScreen(channel, widget.filteredItems);
                    } else {
                      widget.onLiveChannelSelected(channel);
                    }
                  },
                  onLongSelect: () => _handleToggleItemFavorite(channel),
                  builder: (context, isFocused) => AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: isFocused
                          ? const Color(0xFF00E5FF).withOpacity(0.18)
                          : isSelected
                              ? Colors.white.withOpacity(0.07)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isFocused
                            ? const Color(0xFF00E5FF)
                            : isSelected
                                ? const Color(0xFF00E5FF).withOpacity(0.4)
                                : Colors.transparent,
                        width: isFocused ? 2.0 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          alignment: Alignment.center,
                          child: Text(
                            '${idx + 1}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: isSelected || isFocused
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white38,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        buildChannelLogo(channel.logo, size: 38, isLocked: isLocked),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Fonte ligeiramente reduzida (13.5) conforme solicitado
                              Text(
                                channel.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: isSelected || isFocused
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? const Color(0xFF00E5FF)
                                      : Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                channel.group,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isFav) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 17),
                        ],
                        const SizedBox(width: 8),
                        buildQualityBadge(channel.qualityTag),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        const SizedBox(width: 16),

        // Coluna Direita: Painel de Pré-visualização ao Vivo (Com Transição Fluida)
        Expanded(
          flex: 54,
          child: _buildLivePreviewPanel(),
        ),
      ],
    );
  }

  Widget _buildLivePreviewPanel() {
    final previewChannel = widget.selectedLiveChannel;
    if (previewChannel == null) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0E121B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Text(
            'Selecione um canal na lista ao lado para assistir',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }

    final isFav = widget.favorites.contains(previewChannel.id);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E121B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Janela de Vídeo da Pré-visualização
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: Colors.black,
                child: ListenableBuilder(
                  listenable: _engine,
                  builder: (context, _) {
                    // BLINDAGEM DE SUPERFÍCIE: Libera imediatamente o SurfaceView ao abrir a tela cheia
                    if (_engine.isFullScreenActive) {
                      return const SizedBox.expand(
                        child: ColoredBox(color: Colors.black),
                      );
                    }

                    final ctrl = _engine.controller;
                    final isReady = _engine.isReady &&
                        ctrl != null &&
                        ctrl.value.isInitialized &&
                        !_engine.hasError;

                    if (_engine.hasError) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Colors.redAccent, size: 32),
                            const SizedBox(height: 8),
                            const Text(
                              'Sinal indisponível no momento',
                              style: TextStyle(fontSize: 12.5, color: Colors.white70),
                            ),
                            const SizedBox(height: 10),
                            TVFocusableItem(
                              autoScroll: false,
                              onSelect: () => _engine.openStream(
                                previewChannel,
                                forceReload: true,
                                tryHlsFallback: true,
                              ),
                              builder: (c, f) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: f ? Colors.white : const Color(0xFF00E5FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Reconectar Sinal',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (!isReady) {
                      return const Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                      );
                    }

                    final ratio =
                        ctrl.value.aspectRatio > 0 ? ctrl.value.aspectRatio : (16 / 9);

                    return GestureDetector(
                      onTap: () =>
                          widget.onOpenFullScreen(previewChannel, widget.filteredItems),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: ratio,
                          child: VideoPlayer(
                            ctrl,
                            key: ValueKey(
                              'prev_${previewChannel.id}_${_engine.activeFormatLabel}',
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Rodapé da Pré-visualização: Nome do Canal + Botões Tela Cheia e Favorito
          Row(
            children: [
              buildChannelLogo(previewChannel.logo, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      previewChannel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    ListenableBuilder(
                      listenable: _engine,
                      builder: (context, _) {
                        final epg = _engine.currentEpg?.nowTitle ?? previewChannel.group;
                        return Text(
                          epg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: Colors.white60),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Botão Favoritar no Painel
              TVFocusableItem(
                autoScroll: false,
                onSelect: () => _handleToggleItemFavorite(previewChannel),
                builder: (c, f) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: f
                        ? Colors.amber
                        : isFav
                            ? Colors.amber.withOpacity(0.15)
                            : Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: f
                          ? Colors.white
                          : isFav
                              ? Colors.amber
                              : Colors.white24,
                    ),
                  ),
                  child: Icon(
                    isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 18,
                    color: f ? Colors.black : (isFav ? Colors.amber : Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Botão Expandir para Tela Cheia
              TVFocusableItem(
                focusNode: _previewFullScreenBtnNode,
                autoScroll: false,
                onMoveLeft: () {
                  if (_firstLiveChannelFocusNode.canRequestFocus) {
                    _firstLiveChannelFocusNode.requestFocus();
                  }
                },
                onSelect: () =>
                    widget.onOpenFullScreen(previewChannel, widget.filteredItems),
                builder: (c, f) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: f ? Colors.white : const Color(0xFF00E5FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fullscreen_rounded, color: Colors.black, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Tela Cheia',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SEÇÕES 1, 2, 3 e 4: FILMES, SÉRIES, FAVORITOS (3 SUBCATEGORIAS) E HISTÓRICO
  // ===========================================================================
  Widget _buildCatalogAndFavoritesSection() {
    String sectionTitle = 'Filmes';
    IconData sectionIcon = Icons.movie_creation_rounded;

    if (widget.activeSection == 2) {
      sectionTitle = 'Séries';
      sectionIcon = Icons.video_library_rounded;
    } else if (widget.activeSection == 3) {
      sectionTitle = 'Meus Favoritos';
      sectionIcon = Icons.star_rounded;
    } else if (widget.activeSection == 4) {
      sectionTitle = 'Histórico Recente';
      sectionIcon = Icons.history_rounded;
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho Superior: Título + Dica de Favoritar + Botão de Pesquisa
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
            child: Row(
              children: [
                Icon(sectionIcon, color: const Color(0xFF00E5FF), size: 24),
                const SizedBox(width: 10),
                Text(
                  sectionTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                      SizedBox(width: 5),
                      Text(
                        'Segure OK para Favoritar',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _buildSearchButton(
                  focusNode: _vodSearchFocusNode,
                  title: 'Pesquisar em $sectionTitle',
                  onMoveDown: () {
                    if (widget.categories.isNotEmpty &&
                        _firstVodCatFocusNode.canRequestFocus) {
                      _firstVodCatFocusNode.requestFocus();
                    } else if (_firstCatalogItemFocusNode.canRequestFocus) {
                      _firstCatalogItemFocusNode.requestFocus();
                    }
                  },
                ),
              ],
            ),
          ),

          // Barra de Categorias (Em Favoritos exibe as 3 subcategorias: Canais, Filmes e Séries)
          if (widget.categories.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.builder(
                controller: _vodCategoryScrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: widget.categories.length,
                itemBuilder: (context, idx) {
                  final cat = widget.categories[idx];
                  final isSelected = cat == widget.selectedCategory;

                  return TVFocusableItem(
                    focusNode: idx == 0 ? _firstVodCatFocusNode : null,
                    onMoveLeft: idx == 0 ? _focusActiveSidebarItem : null,
                    onMoveUp: () {
                      if (_vodSearchFocusNode.canRequestFocus) {
                        _vodSearchFocusNode.requestFocus();
                      }
                    },
                    onMoveDown: () => _focusFirstItemOfSelectedCategory(),
                    onSelect: () {
                      // REGRA SOLICITADA: Ao selecionar qualquer categoria em Filmes/Séries/Favoritos,
                      // o foco do cursor vai automaticamente para o 1º item daquela categoria.
                      _pendingFocusFirstCatalogItem = true;
                      if (widget.selectedCategory == cat) {
                        _pendingFocusFirstCatalogItem = false;
                        if (_catalogCarouselScrollController.hasClients) {
                          _catalogCarouselScrollController.jumpTo(0);
                        }
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _focusFirstItemOfSelectedCategory();
                        });
                      } else {
                        widget.onCategorySelected(cat);
                      }
                    },
                    builder: (context, isFocused) => _buildCategoryPill(
                      label: widget.activeSection == 3 ? _formatFavoriteSubcategoryLabel(cat) : cat,
                      isSelected: isSelected,
                      isFocused: isFocused,
                      icon: widget.activeSection == 3 ? _getFavoriteSubcategoryIcon(cat) : null,
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 12),

          // Conteúdo Principal:
          // - Se estiver em Favoritos -> Subcategoria Canais: mostra a lista única de canais favoritos + prévia
          // - Se estiver em Filmes, Séries ou Favoritos (Filmes/Séries): mostra o carrossel de pôsteres
          Expanded(
            child: _isFavoritesLiveSubcategory
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: _buildLiveChannelsAndPreviewBody(),
                  )
                : _buildPosterCatalogBody(),
          ),
        ],
      ),
    );
  }

  String _formatFavoriteSubcategoryLabel(String cat) {
    if (cat == 'Canais' || cat == 'TV ao Vivo') return 'TV ao Vivo (Canais)';
    if (cat == 'Filmes') return 'Filmes Favoritos';
    if (cat == 'Séries') return 'Séries Favoritas';
    return cat;
  }

  IconData? _getFavoriteSubcategoryIcon(String cat) {
    if (cat == 'Canais' || cat == 'TV ao Vivo') return Icons.live_tv_rounded;
    if (cat == 'Filmes') return Icons.movie_creation_rounded;
    if (cat == 'Séries') return Icons.video_library_rounded;
    return null;
  }

  Widget _buildPosterCatalogBody() {
    final isSeriesMode = _isDisplayingSeries;
    final itemCount =
        isSeriesMode ? widget.groupedSeries.length : widget.filteredItems.length;

    if (itemCount == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.activeSection == 3
                  ? Icons.star_border_rounded
                  : Icons.movie_filter_outlined,
              size: 54,
              color: Colors.white24,
            ),
            const SizedBox(height: 12),
            Text(
              widget.activeSection == 3
                  ? 'Nenhum item nesta subcategoria de Favoritos.\nSegure o botão OK sobre um filme ou série para adicioná-lo aqui!'
                  : 'Nenhum conteúdo encontrado para esta seleção.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13.5, height: 1.4),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final cardHeight = (availableHeight * 0.86).clamp(210.0, 320.0);
        final cardWidth = cardHeight * 0.67;

        return Center(
          child: SizedBox(
            height: cardHeight,
            child: ListView.builder(
              controller: _catalogCarouselScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: itemCount,
              itemBuilder: (context, idx) {
                if (isSeriesMode) {
                  final series = widget.groupedSeries[idx];
                  final isFav = _isSeriesFavorited(series);
                  final totalEps = series.seasons.values
                      .fold<int>(0, (sum, list) => sum + list.length);

                  return Container(
                    width: cardWidth,
                    margin: const EdgeInsets.only(right: 16),
                    child: TVFocusableItem(
                      focusNode: idx == 0 ? _firstCatalogItemFocusNode : null,
                      onMoveLeft: idx == 0 ? _focusActiveSidebarItem : null,
                      onMoveUp: () {
                        if (widget.categories.isNotEmpty &&
                            _firstVodCatFocusNode.canRequestFocus) {
                          _firstVodCatFocusNode.requestFocus();
                        } else if (_vodSearchFocusNode.canRequestFocus) {
                          _vodSearchFocusNode.requestFocus();
                        }
                      },
                      onSelect: () => widget.onOpenSeriesDetails(series),
                      onLongSelect: () => _handleToggleSeriesFavorite(series),
                      builder: (context, isFocused) => buildStreamingPosterCard(
                        title: series.title,
                        subtitle:
                            '${series.seasons.length} Temp • $totalEps Episódios',
                        logoUrl: series.logo,
                        badgeText: 'SÉRIE',
                        isFocused: isFocused,
                        isFavorite: isFav,
                        onTap: () => widget.onOpenSeriesDetails(series),
                        onLongPress: () => _handleToggleSeriesFavorite(series),
                      ),
                    ),
                  );
                } else {
                  final item = widget.filteredItems[idx];
                  final isFav = widget.favorites.contains(item.id);
                  final isLocked = item.isAdult && !widget.isAdultUnlocked;
                  final prog = widget.watchProgress[item.id];

                  return Container(
                    width: cardWidth,
                    margin: const EdgeInsets.only(right: 16),
                    child: TVFocusableItem(
                      focusNode: idx == 0 ? _firstCatalogItemFocusNode : null,
                      onMoveLeft: idx == 0 ? _focusActiveSidebarItem : null,
                      onMoveUp: () {
                        if (widget.categories.isNotEmpty &&
                            _firstVodCatFocusNode.canRequestFocus) {
                          _firstVodCatFocusNode.requestFocus();
                        } else if (_vodSearchFocusNode.canRequestFocus) {
                          _vodSearchFocusNode.requestFocus();
                        }
                      },
                      onSelect: () async {
                        if (isLocked) {
                          final ok = await widget.onUnlockAdult();
                          if (!ok) return;
                        }
                        widget.onOpenMovieDetails(item);
                      },
                      onLongSelect: () => _handleToggleItemFavorite(item),
                      builder: (context, isFocused) => buildStreamingPosterCard(
                        title: item.name,
                        subtitle: item.group,
                        logoUrl: item.logo,
                        badgeText: item.qualityTag,
                        isFocused: isFocused,
                        isFavorite: isFav,
                        isAdultLocked: isLocked,
                        hasDualAudio: item.audioOptions.length > 1,
                        isSubtitledOnly: item.isSubtitled,
                        progress: prog,
                        onTap: () => widget.onOpenMovieDetails(item),
                        onLongPress: () => _handleToggleItemFavorite(item),
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // COMPONENTES AUXILIARES DE TOPO (BUSCA E PÍLULAS DE CATEGORIA)
  // ===========================================================================
  Widget _buildSearchButton({
    required FocusNode focusNode,
    required String title,
    required VoidCallback onMoveDown,
  }) {
    final hasQuery = widget.searchQuery.trim().isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TVFocusableItem(
          focusNode: focusNode,
          autoScroll: false,
          onMoveLeft: _focusActiveSidebarItem,
          onMoveDown: onMoveDown,
          onSelect: () => showTVVirtualKeyboard(
            context,
            widget.searchController,
            title,
            onChanged: widget.onSearchChanged,
          ),
          builder: (context, isFocused) => AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isFocused
                  ? const Color(0xFF00E5FF)
                  : const Color(0xFF131824),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isFocused
                    ? Colors.white
                    : hasQuery
                        ? const Color(0xFF00E5FF)
                        : Colors.white24,
                width: isFocused ? 1.8 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 17,
                  color: isFocused ? Colors.black : const Color(0xFF00E5FF),
                ),
                const SizedBox(width: 8),
                Text(
                  hasQuery ? 'Busca: "${widget.searchQuery}"' : 'Pesquisar',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: isFocused ? Colors.black : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasQuery) ...[
          const SizedBox(width: 8),
          TVIconButton(
            icon: Icons.clear_rounded,
            size: 16,
            onPressed: () {
              widget.searchController.clear();
              widget.onSearchChanged('');
            },
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryPill({
    required String label,
    required bool isSelected,
    required bool isFocused,
    IconData? icon,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isFocused
            ? const Color(0xFF00E5FF)
            : isSelected
                ? const Color(0xFF00E5FF).withOpacity(0.16)
                : const Color(0xFF111622),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isFocused
              ? Colors.white
              : isSelected
                  ? const Color(0xFF00E5FF)
                  : Colors.white12,
          width: isFocused ? 1.8 : 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 15,
              color: isFocused
                  ? Colors.black
                  : isSelected
                      ? const Color(0xFF00E5FF)
                      : Colors.white70,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isFocused || isSelected ? FontWeight.w900 : FontWeight.w600,
              color: isFocused
                  ? Colors.black
                  : isSelected
                      ? const Color(0xFF00E5FF)
                      : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
