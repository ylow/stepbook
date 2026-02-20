<template>
  <div class="sequence-grid">
    <div
      v-for="seq in sequences"
      :key="seq.id"
      class="sequence-card"
      @click="$router.push(`/book/${props.bookId}/sequence/${seq.id}`)"
    >
      <div class="card-thumbnail">
        <img v-if="seq.thumbnail_path" :src="`/images/${seq.thumbnail_path}`" alt="" />
        <div v-else class="no-thumbnail">No images</div>
      </div>
      <div class="card-info">
        <h3>{{ seq.title }}</h3>
        <span class="step-count">{{ seq.step_count }} step{{ seq.step_count !== 1 ? 's' : '' }}</span>
      </div>
      <button class="export-btn" @click.stop="$emit('export', seq.id)" title="Export as zip">&#8615;</button>
      <button class="delete-btn" @click.stop="$emit('delete', seq.id)" title="Delete">&times;</button>
    </div>
  </div>
</template>

<script setup>
const props = defineProps({
  sequences: { type: Array, required: true },
  bookId: { type: String, required: true }
})
defineEmits(['delete', 'export'])
</script>

<style scoped>
.sequence-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: 20px;
}

.sequence-card {
  background: var(--bg-surface);
  border-radius: var(--radius-lg);
  border: 1px solid var(--border);
  overflow: hidden;
  cursor: pointer;
  transition: transform var(--transition-fast), box-shadow var(--transition-fast);
  position: relative;
}

.sequence-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.3), 0 0 0 1px rgba(100, 181, 246, 0.1);
}

.card-thumbnail {
  width: 100%;
  height: 160px;
  overflow: hidden;
  background: var(--bg-elevated);
}

.card-thumbnail img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.no-thumbnail {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  color: var(--text-muted);
  font-size: 14px;
  background: linear-gradient(135deg, var(--bg-elevated) 0%, var(--bg-surface) 100%);
}

.card-info {
  padding: var(--space-md) var(--space-lg);
}

.card-info h3 {
  font-size: 16px;
  margin-bottom: var(--space-xs);
}

.step-count {
  font-size: 12px;
  color: var(--text-muted);
}

.export-btn,
.delete-btn {
  position: absolute;
  top: var(--space-sm);
  background: rgba(0, 0, 0, 0.6);
  border: none;
  border-radius: 50%;
  width: 28px;
  height: 28px;
  font-size: 18px;
  padding: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  opacity: 0;
  transition: opacity var(--transition-fast), background var(--transition-fast);
}

.export-btn {
  right: 42px;
  color: var(--border-focus);
}

.delete-btn {
  right: var(--space-sm);
  color: var(--danger);
}

.export-btn:hover,
.delete-btn:hover {
  background: rgba(0, 0, 0, 0.8);
}

.sequence-card:hover .export-btn,
.sequence-card:hover .delete-btn {
  opacity: 1;
}

@media (hover: none) and (pointer: coarse) {
  .delete-btn,
  .export-btn {
    opacity: 1;
  }
}
</style>
