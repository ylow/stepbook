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
  background: #2a2a3e;
  border-radius: 8px;
  overflow: hidden;
  cursor: pointer;
  transition: transform 0.15s, box-shadow 0.15s;
  position: relative;
}

.sequence-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 20px rgba(0,0,0,0.3);
}

.card-thumbnail {
  width: 100%;
  height: 160px;
  overflow: hidden;
  background: #1e1e30;
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
  color: #666;
  font-size: 14px;
}

.card-info {
  padding: 12px 16px;
}

.card-info h3 {
  font-size: 16px;
  margin-bottom: 4px;
}

.step-count {
  font-size: 12px;
  color: #888;
}

.delete-btn {
  position: absolute;
  top: 8px;
  right: 8px;
  background: rgba(0,0,0,0.6);
  color: #ff5252;
  border: none;
  border-radius: 50%;
  width: 28px;
  height: 28px;
  font-size: 18px;
  padding: 0;
  display: none;
  align-items: center;
  justify-content: center;
}

.export-btn {
  position: absolute;
  top: 8px;
  right: 42px;
  background: rgba(0,0,0,0.6);
  color: #64b5f6;
  border: none;
  border-radius: 50%;
  width: 28px;
  height: 28px;
  font-size: 18px;
  padding: 0;
  display: none;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

.sequence-card:hover .export-btn {
  display: flex;
}

.sequence-card:hover .delete-btn {
  display: flex;
}

@media (hover: none) and (pointer: coarse) {
  .delete-btn,
  .export-btn {
    display: flex;
  }
}
</style>
