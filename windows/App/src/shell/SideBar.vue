<script setup lang="ts">
type Section = { readonly id: string; readonly label: string; readonly ready: boolean }

defineProps<{ sections: readonly Section[]; active: string }>()
const emit = defineEmits<{ select: [id: string] }>()
</script>

<template>
  <nav class="sidebar">
    <button
      v-for="section in sections"
      :key="section.id"
      class="sidebar__item"
      :class="{ 'sidebar__item--active': section.id === active, 'sidebar__item--pending': !section.ready }"
      type="button"
      @click="emit('select', section.id)"
    >
      {{ section.label }}<span v-if="!section.ready" class="sidebar__mark">⬜</span>
    </button>
  </nav>
</template>

<style scoped>
.sidebar {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-hair);
  width: var(--ds-metric-sidebar-width);
  padding: var(--ds-spacing-s);
  background: var(--ds-color-surface-sidebar);
  border-right: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.sidebar__item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  min-height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-s);
  background: transparent;
  color: var(--ds-color-text-primary);
  border: 1px solid transparent;
  border-radius: var(--ds-radius-control);
  font-size: var(--ds-font-body-size);
  text-align: left;
  cursor: pointer;
}

.sidebar__item:hover {
  background: var(--ds-color-surface-panel);
}

.sidebar__item--active {
  background: var(--ds-color-surface-raised);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.sidebar__item--pending {
  color: var(--ds-color-text-tertiary);
}

.sidebar__mark {
  font-size: var(--ds-font-caption-size);
}
</style>
